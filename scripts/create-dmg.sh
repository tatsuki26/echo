#!/usr/bin/env bash
# Echo.app から DMG を作成
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT/build/export/Echo.app}"
DMG_DIR="$ROOT/build/dmg"
DMG_PATH="$ROOT/build/Echo.dmg"
VOLUME_NAME="Echo"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Echo.app が見つかりません: $APP_PATH" >&2
  echo "先に ./scripts/build-release.sh を実行してください。" >&2
  exit 1
fi

echo "==> Prepare DMG layout"
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

echo "==> Create DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "✅ DMG created: $DMG_PATH"
