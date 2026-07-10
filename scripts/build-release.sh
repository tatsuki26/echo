#!/usr/bin/env bash
# Echo リリースビルドスクリプト
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Echo.xcodeproj"
SCHEME="Echo"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Echo.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Echo.app"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Clean"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archive ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  archive

echo "==> Export"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist"

echo ""
echo "✅ Build complete: $APP_PATH"
echo "   Next: ./scripts/create-dmg.sh"
