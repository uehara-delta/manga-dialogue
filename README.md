# manga-dialogue

Kindle for Mac / Kindle for PC に表示した漫画の画面を自動でキャプチャし、
Anthropic API（Claude）で「キャラ名＋セリフ」形式に文字起こしする個人用ツールです。

- DRM 解除や画面保護の回避は一切行いません。表示されている画面を撮影するだけです
- 抽出結果は個人利用に限り、公開・配布しないでください

## 動作環境

- Python 3.12 以上（`uv` が自動で取得します）
- [uv](https://docs.astral.sh/uv/)
- Mac: Kindle for Mac（Windows 版は現在スタブのみで未対応）

## セットアップ

### 1. uv のインストール

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. 依存パッケージのインストール

```bash
git clone <このリポジトリ>
cd manga-dialogue
uv sync
```

### 3. Anthropic API キーの取得

1. https://console.anthropic.com/ にアクセスしてアカウントを作成（またはログイン）
2. 左メニューの **Billing** でクレジットを購入（従量課金・前払い制）
3. 左メニューの **API Keys** → **Create Key** をクリック
4. 任意の名前を付けて作成し、表示されたキー（`sk-ant-api03-...`）をコピー
   - キーはこの画面でしか確認できません。閉じる前に控えてください

### 4. API キーの設定

環境変数 `ANTHROPIC_API_KEY` で渡します。以下のいずれかの方法を使ってください。

**方法 A: `.env` ファイル（推奨）**

プロジェクト直下に `.env` を作成します（`.gitignore` 済みなのでコミットされません）。

```
ANTHROPIC_API_KEY=sk-ant-api03-...
```

実行時に `--env-file .env` を付けると読み込まれます。

```bash
uv run --env-file .env manga-dialogue extract "作品名"
```

毎回付けるのが面倒な場合は、シェルに `export UV_ENV_FILE=.env` を設定しておくと
`uv run` が自動で読み込みます。

**方法 B: シェルの環境変数**

`.zshrc` などに追記します。

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```

いずれの場合もキーをリポジトリにコミットしないでください。

### 5. Mac の権限設定

初回実行時に以下の許可を求められます。**システム設定 → プライバシーとセキュリティ** から、
コマンドを実行しているターミナルアプリ（Terminal / iTerm2 / VS Code 等）に許可を与えてください。

| 項目 | 用途 |
|---|---|
| 画面収録 | Kindle ウィンドウのスクリーンショット |
| アクセシビリティ | ページ送りのキー入力送信 |

許可後はターミナルを再起動してください。

**tmux を使っている場合の注意**: tmux サーバーはターミナルから切り離されて動くため、
macOS は権限の主体を iTerm 等ではなく `tmux` 自身として扱います。iTerm に許可を与えても
tmux 内からは効きません。**tmux を使わない素のターミナルタブで実行**するのが最も簡単です。
どうしても tmux 内で動かしたい場合は、アクセシビリティの「+」ダイアログで ⌘⇧G を押し、
`realpath $(which tmux)` で得られる実体パス（例: `/opt/homebrew/Cellar/tmux/3.4_1/bin/tmux`）を
入力して追加してください（tmux 更新のたびに再登録が必要です）。

## 使い方

作業データはすべて `works/<作品名>/` 配下に作品ごとに保存されます。
キャプチャは巻ごと、キャラ台帳と抽出結果は **run** ごとに分かれます。run は「どのモデル・
どの設定で抽出したか」の単位で、モデルを変えて結果を比較するときに別 run を使います。

```
works/<作品名>/
├── volumes/
│   ├── 01/captures/             # 0001.png, ...（run 間で共有）
│   └── 02/captures/
└── runs/
    ├── default/                 # 既定の run
    │   ├── characters.json      # キャラ台帳（作品全体で共有。extract が自動生成・更新）
    │   ├── pending_renames.jsonl
    │   └── volumes/01/output/   # 0001.json, ...
    └── gemini/                  # 例: 別モデルで抽出した run
        └── ...
```

- `capture` / `extract` / `repass` は `--volume N`（既定 1）で巻を指定します。
  2 巻以降は 1 巻で育った台帳を引き継いで抽出されるため、話者特定の精度が上がります
- `extract` / `repass` / `consolidate` / `rename` / `fix` / `export` は `--run 名前`（既定 `default`）で
  対象の run を指定します。新しい run を既存 run の台帳から始めるには
  `extract ... --run gemini --from-run default` のように `--from-run` を付けます

### Step 1: キャプチャ

1. Kindle for Mac で対象の本を開き、**1ページ目を表示**した状態にする
2. 以下を実行する

```bash
uv run manga-dialogue capture "作品名"
```

Kindle が自動で前面化され、スペースキーでページ送りしながら撮影します。
**実行中はマウス・キーボードに触れないでください。**
ページ送り後に画面が変化しなくなった時点（最終ページ）で自動停止します。

| オプション | 既定値 | 説明 |
|---|---|---|
| `--max-pages` | 300 | 最大ページ数（安全装置） |
| `--delay` | 1.0 | ページ送り後の待機秒数。描画が間に合わない場合は増やす |
| `--key` | space | ページ送りキー。`left` / `right` も指定可 |
| `--start` | 1 | ファイル名の開始番号。途中から撮り直すときに使う |
| `--volume` | 1 | 巻番号 |
| `--root` | works | 作品ルートディレクトリ |

例: 描画が遅いので 2 秒待ち、←キーで送る

```bash
uv run manga-dialogue capture "作品名" --delay 2 --key left
```

撮影後、`works/作品名/captures/` の画像を確認し、白紙や重複があれば削除してから次へ進んでください。

### Step 2: セリフ抽出

```bash
uv run manga-dialogue extract "作品名"
```

`captures/` の画像を番号順に Claude へ送り、1ページごとに `output/NNNN.json` を書き出します。
新しく登場したキャラは `characters.json` に自動追記され、次のページ以降のプロンプトに反映されます。

**名前がまだ分からないキャラの扱い（仮名）**: 継続登場しそうな人物は「主人公の母（仮）」のような
仮名で台帳に登録され、以降のページでも同じ仮名で話者が紐づきます。後のページで本名が判明すると
LLM が改名指示を返し、confidence が `--rename-threshold`（既定 0.8）以上なら台帳を更新
（仮名は `aliases` に残る）し、**出力済み JSON の speaker も一括で置き換え**ます。
閾値未満の候補は `works/<作品名>/pending_renames.jsonl` に記録されるだけなので、
内容を確認して `rename` コマンドで手動適用してください。

| オプション | 既定値 | 説明 |
|---|---|---|
| `--model` | claude-opus-5 | 使用するモデル。`claude-*`（Anthropic）または `gemini-*`（Google）。詳細は下記 |
| `--run` / `--from-run` | default / – | 結果を保存する run と、台帳のコピー元 run |
| `--resume` | off | 出力済みのページをスキップして途中から再開 |
| `--rename-threshold` | 0.8 | この confidence 以上の改名指示を自動適用 |
| `--volume` | 1 | 巻番号 |
| `--root` | works | 作品ルートディレクトリ |

途中でエラーになった場合は `--resume` を付けて再実行してください。

```bash
uv run manga-dialogue extract "作品名" --resume
```

#### モデルの選択（Anthropic / Google Gemini）

`--model` の名前でプロバイダが自動的に選ばれます。

| 接頭辞 | プロバイダ | API キー | 例 |
|---|---|---|---|
| `claude-` | Anthropic | `ANTHROPIC_API_KEY` | `claude-opus-5`（既定）、`claude-sonnet-5` |
| `gemini-` | Google Gemini | `GEMINI_API_KEY` | `gemini-3.7-flash` |

Gemini の API キーは https://aistudio.google.com/ の **Get API key** から取得し、`.env` に
`GEMINI_API_KEY=...` を追記します。モデルを変えて比較するときは run を分けてください。

```bash
uv run --env-file .env manga-dialogue extract "作品名" --model gemini-3.7-flash --run gemini --from-run default
uv run manga-dialogue export "作品名" --run gemini --format tsv
```

### Step 3: 再抽出（repass）

序盤のページは、後で判明する名前や登場人物を知らない状態で処理されているため、
`不明` や低 confidence が残りがちです。`repass` はその時点までに処理した範囲の台帳
（作品が完結している必要はありません）を使って、`不明` または低 confidence のセリフを含む
ページだけを再抽出し、出力 JSON を上書きします。仮名の改名で解決しなかったケースの救済策です。

```bash
uv run manga-dialogue repass "作品名"
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `--min-confidence` | 0.5 | この値未満の confidence を含むページを対象にする（0 にすると `不明` を含むページのみ） |
| `--all` | off | 条件に関係なく全ページを再抽出 |
| `--page N` | – | 指定ページだけ再抽出（複数指定可） |
| `--dry-run` | off | 対象ページの一覧だけ表示（費用なし） |
| `--volume` | （全巻） | 巻番号。省略すると全巻が対象 |
| `--model` | claude-opus-5 | 使用するモデル |

対象ページ分の API 費用が再度かかります。先に `--dry-run` で件数を確認してください。
再抽出したページは JSON に `"repassed": true` が付きます。

### Step 4: 台帳の整理（consolidate）

ページ単位の抽出では、名前が呼ばれたページと人物がよく見えるページがずれて
仮名が解決されないことがあります。`consolidate` は台帳と全巻の全セリフをテキストで
まとめて 1 回だけ LLM に渡し、「仮名 → 実名」「同一人物の重複統合」を根拠付きで
提案させます。画像を送らないので費用はごく小さく、`--dry-run` で提案だけ確認できます。

```bash
uv run manga-dialogue consolidate "作品名" --dry-run   # 提案を見る
uv run manga-dialogue consolidate "作品名"             # 閾値以上を適用
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `--rename-threshold` | 0.8 | この confidence 以上の提案を自動適用。未満は `pending_renames.jsonl` に記録 |
| `--dry-run` | off | 提案を表示するだけ |

`extract` / `repass` の実行中には使わないでください（台帳が上書きされます）。
統合後に `repass` を再実行すると、統合された名前で再抽出されます。

### AI による一括修正（fix）

「『うう』の話者をユルの母にして」のような指示文で、範囲内のセリフの修正案を LLM に作らせます。
既定では提案を表示するだけで、`--apply` を付けると適用します。適用した行には `manual` が付き、
以降の `repass` で上書きされません。

```bash
uv run manga-dialogue fix "作品名" --volume 1 --page 5 -i "「うう」の話者を「主人公の母（仮）」にする"
uv run manga-dialogue fix "作品名" --volume 1 -i "『不明』のうち尻尾が明確なものを再判定" --with-images --apply
```

| オプション | 既定値 | 説明 |
|---|---|---|
| `-i` / `--instruction` | 必須 | 修正の指示文 |
| `--volume` / `--page` | 全巻 / 全ページ | 対象範囲 |
| `--with-images` | off | 対象ページの画像も送る（話者の再判定などに。費用増） |
| `--apply` | off | 変更案を適用する |

### 手動での改名（rename）

仮名や誤った名前を手で直したいときは `rename` を使います。台帳を更新し、出力済み JSON の
speaker（「〜（心の声）」も含む）を置き換えます。API は呼びません。

```bash
uv run manga-dialogue rename "作品名" "主人公の母（仮）" "花子"
```

### エクスポート（export）

```bash
uv run manga-dialogue export "作品名"                    # works/<作品名>/<作品名>.csv
uv run manga-dialogue export "作品名" --format tsv --volume 1
uv run manga-dialogue export "作品名" --format markdown --out ~/Desktop/dialogue.md
```

列: `volume, page, panel, speaker, text, confidence, basis, manual`。Markdown はページごとの見出し付きです。

### 手動修正の保護（manual）

出力 JSON の行に `"manual": true`（またはページに `"manual": true`）を付けると、そのページは
`repass` の対象から外れます（`--force` で含められます）。`fix --apply` で変更した行にも自動で付きます。
`rename` は manual な行にも適用されます。

### GUI 連携（--json）

すべてのコマンドは `--json` を付けると、人間向けの表示の代わりに JSON Lines を stdout に出します。
GUI などから子プロセスとして呼び出す用途向けです。

```bash
uv run manga-dialogue --json extract "作品名" --volume 1
{"event": "start", "total": 206, "volume": 1}
{"event": "page", "volume": 1, "page": 1, "lines": 5, "new_characters": [], "renames_applied": [], "renames_pending": []}
...
{"event": "done", "characters": 39, "failed": []}
```

主なイベント: `start` / `page` / `page_failed` / `target`（repass の dry-run） / `proposal`（consolidate） /
`change`（fix） / `done` / `error`。失敗時は `error` を出して終了コード 1 になります。

### 出力形式

`output/0001.json`:

```json
{
  "volume": 1,
  "page": 1,
  "image": "0001.png",
  "lines": [
    {"panel": 1, "speaker": "ナレーション", "text": "……", "confidence": 1.0, "basis": "unknown", "x": 0.8, "y": 0.1, "manual": false},
    {"panel": 2, "speaker": "太郎", "text": "……", "confidence": 0.9, "basis": "tail", "x": 0.3, "y": 0.5, "manual": false}
  ],
  "new_characters": [
    {"name": "太郎", "aliases": [], "appearance": "黒髪短髪、学生服"}
  ],
  "renames": [],
  "repassed": false,
  "manual": false
}
```

- `panel`: ページ内のコマ番号（右→左、上→下）
- `speaker`: 話者。ナレーションは `ナレーション`、心の声は `太郎（心の声）`、特定できない場合は `不明`
- `confidence`: 話者特定の確信度（0〜1）
- `basis`: 話者を決めた根拠。`tail`（吹き出しの尻尾）/ `context`（文脈推定。confidence は 0.6 以下）/ `unknown`
- `x`, `y`: 吹き出し中心の位置（画像左上が 0,0、右下が 1,1）。`lines` はコマ番号順、
  同じコマ内は座標から右→左・上→下に並べ替え済み
- `manual`: 手動または `fix` で修正済み。`repass` で上書きされない

### キャラ台帳の手動編集

`characters.json` は手で編集できます。抽出精度を上げるには、最初に主要キャラを登録してから
`extract` を実行するのが効果的です。

```json
{
  "characters": [
    {"name": "太郎", "aliases": ["タロー"], "appearance": "黒髪短髪、学生服、眼鏡"}
  ]
}
```

`aliases` に登録した名前は新キャラとして重複追加されません。

## 料金の目安

1 ページあたり画像 1 枚 + 短いテキストを送信します。モデル別の概算は
https://www.anthropic.com/pricing を参照してください。まず `--max-pages 5` 程度で
少量試し、コンソールの **Usage** で実際の消費を確認してから全巻に進むことを推奨します。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `Kindle のウィンドウが見つかりません` | Kindle で本を開いているか確認。ウィンドウが最小化されていないか確認 |
| 撮影画像が真っ黒 | 「画面収録」の許可がない。許可後にターミナルを再起動 |
| ページが送られない | 「アクセシビリティ」の許可がない、または `--key left` を試す |
| 同じページが 2 枚続けて保存される | `--delay` を増やす（描画が間に合っていない） |
| 1 枚目で即終了する | Kindle が前面化に失敗している。手動で前面にしてから再実行 |
| 画像が壁紙や別ウィンドウになる | ステージマネージャーで Kindle が非アクティブ。一度 Kindle をクリックしてから再実行 |
| tmux 内でページ送りが効かない | 上記「tmux を使っている場合の注意」を参照 |
| `authentication_error` | `ANTHROPIC_API_KEY` が未設定または誤り。`echo $ANTHROPIC_API_KEY` で確認 |
| `rate_limit_error` | しばらく待って `--resume` で再開 |

## 開発

```
src/manga_dialogue/
├── cli.py          # CLI エントリポイント
├── models.py       # データモデル（pydantic）
├── workspace.py    # 作品ディレクトリのパス管理
├── capture/        # OS 依存のキャプチャ層（base / mac / windows）
├── extract/        # 画像 → LLM → JSON（characters / prompt / extractor / consolidate / fix）
│   └── llm/        # プロバイダ抽象化（anthropic_model / gemini_model）
└── output/         # エクスポート（CSV / TSV / Markdown）
```

OS 依存コードは `capture/` にのみ置き、他の層は OS 非依存を保ってください。
