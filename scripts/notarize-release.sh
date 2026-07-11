#!/usr/bin/env bash
# Developer ID 署名 + 公証 + staple まで一括実行
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_PATH="$BUILD_DIR/export/Echo.app"
DMG_PATH="$BUILD_DIR/Echo.dmg"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-echo-notarize}"

require_env() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    echo "環境変数 $name が未設定です。" >&2
    exit 1
  fi
}

check_signing_identity() {
  if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Developer ID Application 証明書が見つかりません。" >&2
    echo "Xcode → Settings → Accounts で Apple ID を追加し、" >&2
    echo "Manage Certificates → Developer ID Application を作成してください。" >&2
    exit 1
  fi
}

check_notary_credentials() {
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    return 0
  fi

  echo "公証用の認証情報が見つかりません。" >&2
  echo "" >&2
  echo "次のいずれかを設定してください:" >&2
  echo "" >&2
  echo "  A) Keychain プロファイル（推奨）:" >&2
  echo "     xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\" >&2
  echo "       --apple-id \"your@email.com\" \\" >&2
  echo "       --team-id \"XXXXXXXXXX\" \\" >&2
  echo "       --password \"app-specific-password\"" >&2
  echo "" >&2
  echo "  B) 環境変数:" >&2
  echo "     NOTARY_APPLE_ID / NOTARY_PASSWORD / NOTARY_TEAM_ID" >&2
  exit 1
}

submit_notary() {
  local target=$1
  echo "==> Submit for notarization: $target"

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$target" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
    return
  fi

  require_env NOTARY_APPLE_ID
  require_env NOTARY_PASSWORD
  require_env NOTARY_TEAM_ID

  xcrun notarytool submit "$target" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" \
    --wait
}

require_env DEVELOPMENT_TEAM
check_signing_identity
check_notary_credentials

echo "==> Build (Developer ID)"
EXPORT_METHOD=developer-id "$ROOT/scripts/build-release.sh"

echo "==> Create DMG"
"$ROOT/scripts/create-dmg.sh"

echo "==> Verify signature (before notarization)"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vv "$APP_PATH" || true

submit_notary "$DMG_PATH"

echo "==> Staple notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler staple "$DMG_PATH"

echo "==> Verify (after staple)"
spctl -a -vv "$APP_PATH"
spctl -a -vv "$DMG_PATH"

echo ""
echo "✅ 公証完了"
echo "   App: $APP_PATH"
echo "   DMG: $DMG_PATH"
echo ""
echo "GitHub リリースを更新する場合:"
echo "   gh release upload v0.1.0-beta \"$DMG_PATH\" --clobber"
