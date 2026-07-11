# Echo 配布ガイド

## 前提

- macOS 14.0 以降
- Xcode 15 以降
- Apple Developer Program（公証・Developer ID 配布の場合）

## ローカルビルド

```bash
chmod +x scripts/*.sh
./scripts/build-release.sh
./scripts/create-dmg.sh
```

成果物:

- `build/export/Echo.app` — アプリ本体
- `build/Echo.dmg` — 配布用 DMG

## コード署名

Xcode の Signing & Capabilities で **Team** を設定するか、環境変数で指定します。

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-release.sh
```

## Developer ID 配布（App Store 外）

### 事前準備（初回のみ）

1. **Apple Developer Program** に加入（年 $99）
2. **Xcode** → Settings → Accounts で Apple ID を追加
3. **Manage Certificates** → **Developer ID Application** を作成
4. [appleid.apple.com](https://appleid.apple.com) で **App用パスワード** を発行
5. 公証用認証情報を Keychain に保存:

```bash
xcrun notarytool store-credentials "echo-notarize" \
  --apple-id "your@email.com" \
  --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Team ID は [developer.apple.com/account](https://developer.apple.com/account) の Membership details で確認できます。

### 一括ビルド + 公証

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/notarize-release.sh
```

成功すると `build/export/Echo.app` と `build/Echo.dmg` が公証済みになります。

### 手動で行う場合

1. `scripts/ExportOptions-developer-id.plist` を使用してエクスポート
2. Developer ID Application 証明書をインストール
3. アーカイブ → エクスポート

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX EXPORT_METHOD=developer-id ./scripts/build-release.sh
./scripts/create-dmg.sh
codesign --verify --deep --strict build/export/Echo.app
spctl -a -vv build/export/Echo.app
```

## 公証（Notarization）

`notarize-release.sh` を使うのが最も簡単です。手動の場合:

```bash
xcrun notarytool submit build/Echo.dmg \
  --keychain-profile "echo-notarize" \
  --wait

xcrun stapler staple build/export/Echo.app
xcrun stapler staple build/Echo.dmg
spctl -a -vv build/Echo.dmg
```

### GitHub リリースの差し替え

```bash
gh release upload v0.1.0-beta build/Echo.dmg --clobber
```

## Gatekeeper（「開発元を確認できないため開けません」）

現在のベータビルドは adhoc 署名のため、インターネット経由で取得した Mac では Gatekeeper にブロックされる場合があります。

**ベータテスター向け回避手順:**

1. `Echo.app` を Applications に配置
2. 右クリック → **「開く」** → ダイアログで **「開く」**

または:

```bash
xattr -cr /Applications/Echo.app
```

**一般配布向け（推奨）:** Developer ID Application 証明書で署名し、`notarytool` で公証してから DMG を配布してください。公証済みアプリは通常のダブルクリックで起動できます。

## ユーザーへのインストール手順

1. `Echo.dmg` を開く
2. `Echo.app` を Applications にドラッグ
3. 初回起動時に権限を許可
   - マイク
   - 音声認識
   - 画面収録（相手の声の取得）
   - アクセシビリティ（ショートカット）
   - ブラウザの自動化（会議検知）

## バージョン更新

`Echo.xcodeproj` の **Marketing Version** と **Current Project Version** を更新してください。

環境設定 → アプリ情報 でバージョンを確認できます。
