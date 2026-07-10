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

1. `scripts/ExportOptions.plist` の `method` を `developer-id` に変更
2. Developer ID Application 証明書をインストール
3. アーカイブ → エクスポート

```bash
codesign --verify --deep --strict build/export/Echo.app
spctl -a -vv build/export/Echo.app
```

## 公証（Notarization）

```bash
xcrun notarytool submit build/Echo.dmg \
  --apple-id "your@email.com" \
  --team-id "XXXXXXXXXX" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple build/export/Echo.app
```

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
