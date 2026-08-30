# manga-dialogue

漫画の電子書籍（Kindle）画面を自動キャプチャし、AIで「キャラ名＋セリフ」形式に
文字起こしするツール。個人利用のみ。抽出結果を公開・配布しない。

## 方針
- 言語: Python 3.12 / パッケージ管理: uv
- 開発環境は Mac（Kindle for Mac で動作確認）、最終ターゲットは Windows（Kindle for PC）
- OS依存コードはキャプチャ層のみに閉じ込める。他の層はOS非依存を厳守
- DRM解除や FLAG_SECURE 回避は一切行わない。表示画面のキャプチャのみ
- まずCLIで1巻通すことを最優先。GUIは後回し

## 構成（3層）
1. capture/  … CaptureDriver 抽象クラス + MacKindleDriver / WindowsKindleDriver
   - ウィンドウ特定・前面化、ページ送り、スクショ（mss）
   - 「ページ送り後に画像が変化しない」ことで最終ページを判定
2. extract/  … 画像 → マルチモーダルLLM（Anthropic API）→ JSON
   - キャラ台帳（名前・外見特徴）をプロンプトに毎回含め、新キャラは台帳に追記
   - 出力: [{page, panel, speaker, text, confidence}]
3. output/   … JSON / CSV / Markdown 出力

## 制約・注意
- Mac では「画面収録」「アクセシビリティ」の許可が必要
- 見開き表示は右→左、上→下のコマ順で読む
- ナレーション・モノローグは speaker="ナレーション" 等で区別
- Windows のexe化は GitHub Actions (windows-latest) + PyInstaller で行う
- APIキーは環境変数 ANTHROPIC_API_KEY。コミットしない
