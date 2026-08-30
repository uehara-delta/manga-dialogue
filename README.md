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

## 使い方

作業データはすべて `works/<作品名>/` 配下に作品ごとに保存されます。

```
works/<作品名>/
├── characters.json   # キャラ台帳（extract が自動生成・更新）
├── captures/         # 0001.png, 0002.png, ...
└── output/           # 0001.json, 0002.json, ...
```

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

| オプション | 既定値 | 説明 |
|---|---|---|
| `--model` | claude-opus-5 | 使用するモデル。コストを抑えるなら `claude-sonnet-5` |
| `--resume` | off | 出力済みのページをスキップして途中から再開 |
| `--root` | works | 作品ルートディレクトリ |

途中でエラーになった場合は `--resume` を付けて再実行してください。

```bash
uv run manga-dialogue extract "作品名" --resume
```

### 出力形式

`output/0001.json`:

```json
{
  "page": 1,
  "image": "0001.png",
  "lines": [
    {"panel": 1, "speaker": "ナレーション", "text": "……", "confidence": 1.0},
    {"panel": 2, "speaker": "太郎", "text": "……", "confidence": 0.9}
  ],
  "new_characters": [
    {"name": "太郎", "aliases": [], "appearance": "黒髪短髪、学生服"}
  ]
}
```

- `panel`: ページ内のコマ番号（右→左、上→下）
- `speaker`: 話者。ナレーションは `ナレーション`、心の声は `太郎（心の声）`、特定できない場合は `不明`
- `confidence`: 話者特定の確信度（0〜1）

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
| `authentication_error` | `ANTHROPIC_API_KEY` が未設定または誤り。`echo $ANTHROPIC_API_KEY` で確認 |
| `rate_limit_error` | しばらく待って `--resume` で再開 |

## 開発

```
src/manga_dialogue/
├── cli.py          # CLI エントリポイント
├── models.py       # データモデル（pydantic）
├── workspace.py    # 作品ディレクトリのパス管理
├── capture/        # OS 依存のキャプチャ層（base / mac / windows）
└── extract/        # 画像 → LLM → JSON（characters / prompt / extractor）
```

OS 依存コードは `capture/` にのみ置き、他の層は OS 非依存を保ってください。
