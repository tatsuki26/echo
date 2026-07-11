#!/usr/bin/env bash
# Echo リリースビルドスクリプト
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Echo.xcodeproj"
SCHEME="Echo"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_METHOD="${EXPORT_METHOD:-mac-application}"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Echo.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Echo.app"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ "$EXPORT_METHOD" == "developer-id" ]]; then
  EXPORT_OPTIONS="$ROOT/scripts/ExportOptions-developer-id.plist"
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "Developer ID ビルドには DEVELOPMENT_TEAM が必要です。" >&2
    echo "例: DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-release.sh" >&2
    exit 1
  fi
else
  EXPORT_OPTIONS="$ROOT/scripts/ExportOptions.plist"
fi

echo "==> Clean"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archive ($CONFIGURATION, $EXPORT_METHOD)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}" \
  archive

echo "==> Export ($EXPORT_METHOD)"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo ""
echo "✅ Build complete: $APP_PATH"
echo "   Next: ./scripts/create-dmg.sh"
