#!/usr/bin/env bash
# ビルド済みエンジン（dist/manga-dialogue-engine）を Flutter アプリに同梱する。
# 使い方: scripts/bundle_engine.sh <app のパス>
#   macOS:   scripts/bundle_engine.sh gui/build/macos/Build/Products/Release/manga_dialogue_gui.app
#   Windows: scripts/bundle_engine.sh gui/build/windows/x64/runner/Release
set -euo pipefail
app="${1:?app path required}"
src="dist/manga-dialogue-engine"
[ -d "$src" ] || { echo "engine not built: $src" >&2; exit 1; }
case "$app" in
  *.app) dest="$app/Contents/Resources/engine" ;;
  *)     dest="$app/engine" ;;
esac
rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
cp -R "$src" "$dest"
echo "bundled engine → $dest"
