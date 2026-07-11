#!/bin/bash
# Echo インストール補助スクリプト（公証前ベータ向け）
set -euo pipefail

APP_NAME="Echo.app"
TARGET="/Applications/$APP_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/$APP_NAME"

echo "==> Echo インストール"
echo ""

if [[ ! -d "$SOURCE" ]]; then
  echo "エラー: $SOURCE が見つかりません。" >&2
  echo "DMG を開いた状態で、このスクリプトを実行してください。" >&2
  exit 1
fi

echo "検疫属性を解除しています..."
xattr -cr "$SOURCE" 2>/dev/null || true

if [[ -d "$TARGET" ]]; then
  echo "既存の $TARGET を置き換えます..."
  rm -rf "$TARGET"
fi

echo "Applications にコピーしています..."
ditto "$SOURCE" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true

echo ""
echo "✅ インストール完了"
echo "   Echo を起動します..."
open "$TARGET"
