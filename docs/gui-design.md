# manga-dialogue GUI 設計

Flutter 製デスクトップアプリ（Mac / Windows）と Python エンジン（既存 CLI）を組み合わせ、
キャプチャ画像と抽出結果を並べて確認・修正し、AI による一括修正とエクスポートを行う。

## 1. 目的とスコープ

### やること（MVP）
- 作品 / run / 巻 / ページを選び、キャプチャ画像と抽出結果を並べて表示
- セリフの手動修正（話者・本文・コマ番号・順序・追加・削除）。修正した行に `manual` を付ける
- キャラ台帳の閲覧・編集（名前・別名・外見）と統合（rename）
- 保留中の改名候補（`pending_renames.jsonl`）のレビューと承認
- エンジン実行: capture / extract / repass / consolidate / fix / export を GUI から起動し、進捗を表示
- AI 一括修正（fix）: 指示文 → 変更案のプレビュー → 適用
- エクスポート（CSV / TSV / Markdown）
- 容量管理: 巻・run 単位でのキャプチャ画像や抽出結果の一括削除、使用容量の表示

### やらないこと（当面）
- 台帳や出力のクラウド同期、複数ユーザー
- GUI からのプロンプト編集（プロンプトはエンジン側の資産として扱う）
- Kindle の操作 UI（キャプチャの開始・停止と結果確認のみ）
- Windows 版の Kindle ドライバ（Mac で先行し、Windows はキャプチャ以外の機能から）

## 2. アーキテクチャ

```
┌──────────────── Flutter アプリ ────────────────┐
│  画面（閲覧・編集・レビュー・ジョブ）              │
│  ┌──────────────┐   ┌──────────────────────┐   │
│  │ Workspace     │   │ EngineService         │   │
│  │ (works/ を直接 │   │ 子プロセス起動         │   │
│  │  読み書き)     │   │ stdout の JSON Lines を │   │
│  └──────┬───────┘   │ イベントとして配信      │   │
│         │           └──────────┬───────────┘   │
└─────────┼──────────────────────┼───────────────┘
          │ ファイル I/O           │ プロセス起動 + stdio
          ▼                      ▼
   works/<作品名>/          manga-dialogue エンジン（Python）
     volumes/NN/captures/     capture / extract / repass / consolidate /
     runs/<run>/              fix / rename / export   （--json）
       characters.json
       pending_renames.jsonl
       volumes/NN/output/NNNN.json
```

原則:
- **閲覧・手動修正はエンジンなしで完結**する。Flutter が `works/` の JSON と PNG を直接読み書きする
- **LLM 呼び出し・Kindle 操作はエンジンに委ねる**。GUI は `--json` のイベントを受け取って表示する
- **同一 run に対する同時操作を避ける**。エンジン実行中はその run を読み取り専用にする（後述のロック）

### エンジンの呼び出し
- 開発時: リポジトリの `uv run manga-dialogue ...` を起動（設定でエンジンのパスと作業ディレクトリを指定）
- 配布時: PyInstaller で作った `manga-dialogue-engine`（Mac: onedir、Windows: exe）をアプリに同梱
- 1 コマンド 1 プロセス。`Process.start` で起動し、stdout を行単位で読んで JSON にデコードする。stderr はログに保存
- 環境変数: API キーはアプリの設定から子プロセスの環境に渡す（`.env` は開発時のみ）
- Mac の画面収録・アクセシビリティ権限は親プロセス（Flutter アプリ）に付与される

## 3. エンジン契約（JSON Lines）

すべて `manga-dialogue --json <command> ...`。1 行 1 イベント、`event` フィールドで種別を表す。

| event | 発生元 | 主なフィールド |
|---|---|---|
| `start` | 全コマンド | `total`, `volume`, `targets`（repass）, `skipped_manual` |
| `page` | capture / extract / repass | `volume`, `page`, `lines`, `new_characters`, `renames_applied`, `renames_pending` |
| `page_failed` | extract / repass | `volume`, `page`, `message` |
| `target` | repass --dry-run | `volume`, `page` |
| `proposal` | consolidate | `status`（適用/保留/候補）, `from_name`, `to_name`, `confidence`, `reason`, `replaced` |
| `change` | fix | `volume`, `page`, `index`, `before`, `speaker`, `text`, `panel`, `reason` |
| `done` | 全コマンド | コマンドごとの集計（`saved`, `characters`, `failed`, `applied`, `path`, `rows` …） |
| `error` | 全コマンド | `message`, `error_type`。終了コード 1（入力エラー）/ 2（課金・認証など回復不能） |

### エンジン側に追加するもの
| 項目 | 内容 |
|---|---|
| `info` コマンド | エンジンのバージョン、対応プロバイダ、API キーの有無、既定モデルを JSON で返す。起動時の疎通確認用 |
| run ロック | エンジンが run を書き換える間 `runs/<run>/.lock`（PID・コマンド・開始時刻）を置き、終了時に消す。GUI はロック中の run を読み取り専用にする |
| `fix --apply-from <file>` | 変更案を JSON で受け取り、GUI で選択した分だけ適用できるようにする |
| `pending` コマンド群 | `pending list` / `pending approve <id>` / `pending reject <id>`。`pending_renames.jsonl` の各行に `id` と `status`（pending / approved / rejected）を持たせ、approve は `rename` を実行して状態を更新する。同じ from→to の候補は 1 件にまとめ、根拠を追記する。判断の記録はエンジンが責任を持ち、GUI は一覧とボタンだけ |
| キャンセル | GUI からの SIGTERM / SIGINT でページ境界で安全に停止（出力 JSON と台帳は 1 ページ単位で書かれているので、途中終了しても壊れない） |
| usage 記録 | `page` イベントに入力・出力トークン数を含め、GUI で概算費用を表示できるようにする |

## 4. データモデル（既存の JSON をそのまま使う）

`output/NNNN.json`（`PageResult`）:

```json
{
  "volume": 1, "page": 10, "image": "0010.png",
  "lines": [
    {"panel": 1, "speaker": "太郎", "text": "……", "confidence": 0.9,
     "basis": "tail", "x": 0.73, "y": 0.14, "manual": false}
  ],
  "new_characters": [], "renames": [], "repassed": false, "manual": false
}
```

- GUI の編集は `lines` の要素を書き換え、`manual: true` を付けて保存する。ページ全体を確定したら `manual: true`（ページ）を付ける
- `x`, `y` は画像上のマーカー表示と行の対応付けに使う。行の追加時は画像クリックで座標を与える
- 読み順は `lines` の配列順。GUI ではドラッグで並べ替え可能にし、`panel` は手で編集する
- `characters.json`（`Character`: name / aliases / appearance）は GUI で直接編集。統合（別エントリへのマージ）は出力の speaker も書き換える必要があるため `rename` コマンド経由にする
- `pending_renames.jsonl` は候補ごとに `id` / `status` を持つ状態ファイルとし、エンジンの `pending` コマンドで更新する。GUI は `pending list` の結果を表示し、承認・却下を `pending approve/reject` で依頼する

## 5. 画面構成

### 5.1 ホーム
- `works/` の作品一覧（作品名、巻数、run 一覧、最終更新）
- 作品を選ぶと run と巻を選択してページ編集へ
- 「新規キャプチャ」「抽出を実行」への入口

### 5.2 ページ編集（主画面）
```
┌ 作品名 ▾  run: gemini ▾  巻: 01 ▾   ◀ 0010 / 0104 ▶   [再抽出] [AI修正] [確定] ┐
├──────────────────────────────┬──────────────────────────────────────────┤
│                              │  #  panel  speaker ▾      text          conf basis │
│   キャプチャ画像               │  1    1    太郎           花子！こっち…   0.95 tail  │
│   ・吹き出し位置に番号マーカー    │  2    1    花子           なに、太郎…     0.95 tail  │
│   ・行選択とマーカーが連動       │  3    2    太郎           また一人で…     0.95 tail  │
│   ・クリックで新規行の座標指定    │  …                                                 │
│   ・ズーム / パン               │  [＋行追加] [－削除] [↑↓並べ替え]                     │
│                              │  選択行の詳細: 本文の複数行編集、basis、manual        │
├──────────────────────────────┴──────────────────────────────────────────┤
│ 台帳（折りたたみ）: 名前 / 別名 / 外見 の一覧・編集。speaker のプルダウンの選択肢になる       │
└─────────────────────────────────────────────────────────────────────────┘
```
- 話者の入力は台帳からの選択（「不明」「ナレーション」「文字」を含む）＋自由入力
- 行の背景色で状態を示す: `不明`、低 confidence（< 0.6）、`manual`、`repassed`
- 保存は行編集ごとに即時（ページ JSON を書き戻す）。Undo はページ単位で直前の状態を保持

### 5.3 キャラ台帳
- 一覧（名前、別名、外見、セリフ数）と編集
- 「統合」: 2 エントリを選んで `rename` を実行（プレビューとして置換件数を表示）
- 「保留中の改名候補」タブ: `pending list` の結果を根拠付きで一覧表示し、承認（`pending approve` → rename 実行）/ 却下（`pending reject`）。処理済みは既定で非表示

### 5.4 ジョブ
- 実行中・完了したエンジン処理の一覧（コマンド、対象、進捗バー、経過時間、ログ）
- `page` イベントで進捗を更新。失敗ページ一覧、キャンセルボタン
- 完了後に対象 run を再読込

### 5.5 AI 一括修正（fix）ダイアログ
1. 範囲（巻・ページ・「このページのみ」）と指示文、画像添付の有無を入力
2. エンジンで `fix` を実行し、`change` イベントを表で表示（before / after、理由）
3. チェックした変更だけを適用（`fix --apply-from`）

### 5.6 キャプチャ
- 作品名・巻・ページ送りキー・待機秒数・最大枚数を指定して `capture` を実行
- 「実行中は Mac に触れない」旨の案内。完了後にサムネイル一覧を表示し、不要ページ（Kindle の終了画面など）を削除できる

### 5.7 エクスポート / 設定
- エクスポート: 形式・run・巻・出力先を指定して `export` を実行
- 設定: エンジンのパス（開発 / 同梱）、`works/` の場所、API キー（OS のセキュアストレージに保存）、既定モデル、既定のキャプチャ設定
- 容量管理: 作品・巻・run ごとの使用容量を表示し、キャプチャ画像や run の一括削除を行う（`works/` はアプリが管理し、ユーザーが Finder 等で直接操作することは想定しない）

## 6. Flutter 側の構成

```
gui/                          # Flutter プロジェクト（リポジトリ内）
├── lib/
│   ├── main.dart
│   ├── app.dart              # ルーティング、テーマ
│   ├── engine/               # EngineService: プロセス起動、JSON Lines のパース、ジョブ管理
│   ├── workspace/            # works/ の走査、PageResult / Character の読み書き、ロック検出
│   ├── models/               # PageResult, Line, Character, Rename, LineChange（json_serializable）
│   ├── features/
│   │   ├── home/
│   │   ├── page_editor/      # 画像ビュー（マーカー）、行テーブル、行詳細
│   │   ├── characters/       # 台帳、保留レビュー
│   │   ├── jobs/
│   │   ├── fix/
│   │   ├── capture/
│   │   └── settings/
│   └── widgets/
└── test/
```

- 状態管理: Riverpod（`AsyncNotifier` で run / ページ / ジョブを保持）
- 主なパッケージ: `riverpod`, `go_router`, `json_serializable`, `path`, `file_picker`, `window_manager`, `flutter_secure_storage`（API キー）
- 画像表示: `InteractiveViewer` + `CustomPaint` でマーカーとコマ矩形を重ねる
- 表: `DataTable` ではなく行ウィジェットの `ListView`（インライン編集と並べ替えのため）

## 7. 配布

- エンジン: `packaging/engine.spec`（PyInstaller、onedir）。GitHub Actions（macos-latest / windows-latest）でビルドし、`info` で疎通確認
- GUI: `flutter build macos` / `flutter build windows`（Release）。`scripts/bundle_engine.sh` がエンジンを `Contents/Resources/engine/`（Mac）/ `engine/`（Windows）にコピー
- GUI の `EngineLocator` が同梱エンジンを検出すると既定の起動コマンドにする。開発時は設定でリポジトリの `uv run --env-file .env manga-dialogue` を指定
- `v*` タグで両 OS の zip を Release に添付（`.github/workflows/build.yml`）。署名・公証は未対応

## 8. マイルストーン

| # | 内容 | エンジン側の作業 |
|---|---|---|
| M1 | 閲覧・手動修正・台帳編集（エンジンなしで動く） | なし |
| M2 | ジョブ実行（extract / repass / export / capture）、進捗表示、ロック | `info`、run ロック、usage 記録 |
| M3 | 保留改名レビュー、consolidate、fix（選択適用） | `fix --apply-from` |
| M4 | 配布（PyInstaller + GitHub Actions、エンジン同梱） | ビルド設定 |

M1 は既存の抽出データ（`works/` 配下の run）だけで開発・検証できる。

## 9. 決定事項

- `works/` の既定の場所はリポジトリ（配布時はインストールフォルダ）直下の `works/`。設定で任意のパスに変更できる。エンジンには `--root` で渡す。`works/` の中はアプリが管理し、ユーザーが Finder / エクスプローラーで直接操作することは想定しない（容量管理はアプリの機能として提供）
- 保留中の改名候補の状態（承認 / 却下）はエンジンが `pending` コマンドで管理する。GUI は表示と操作のみ
- Mac を先行して実装する。Windows 版はキャプチャ以外の機能から対応し、Kindle for PC のドライバは後回し
- 既定モデルは `gemini-3.7-flash`（費用・速度・精度のバランスによる判断）
