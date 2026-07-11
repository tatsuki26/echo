# Echo

会議の文字起こし・要約 macOS アプリ（SwiftUI）

## 要件

- macOS 14.0+
- Xcode 15+

## 起動方法

1. `Echo.xcodeproj` を Xcode で開く
2. Scheme `Echo` を選択して Run（⌘R）
3. **メニューバー右側**の波形アイコン「Echo」から操作する（Dock アイコンなし）

メニューバーに収まっている場合は、メニューバー右端の `^` をクリックして探してください。

## 実装済み機能

| 機能 | 説明 |
|------|------|
| リアルタイム文字起こし | Speech Framework + マイク入力 |
| 相手の声の文字起こし | ScreenCaptureKit でブラウザ（Arc 等）の会議音声を取得 |
| Google Meet / Zoom 検知 | 前面ブラウザのタブ URL または Zoom アプリを監視 |
| AI 要約 | OpenAI API（任意）またはオフライン要約 |
| データ永続化 | SwiftData で会議・文字起こし・アクションアイテムを保存 |
| Notion 連携 | 会議詳細を Notion データベースにページ作成 |
| グローバルショートカット | ⌘⇧S 開始/停止 / ⌘O 履歴 / ⌘, 設定 |
| Markdown エクスポート | 会議詳細から .md ファイルで保存 |
| 配布用ビルド | `scripts/build-release.sh` + `scripts/create-dmg.sh` |

## 話者の区別

| ラベル | 音声ソース |
|--------|-----------|
| 話者A | 自分の声（マイク） |
| 話者B | 相手の声（ブラウザの会議音声） |

## 初回セットアップ

### 1. 権限（必須）

| 権限 | 用途 |
|------|------|
| マイク | 自分の声の取得 |
| 音声認識 | 文字起こし |
| 画面収録 | 相手の声（ブラウザ音声）の取得 |
| アクセシビリティ | グローバルショートカット（⌘⇧S 等） |
| 自動化（ブラウザ） | Google Meet タブ URL の取得 |

環境設定（⌘,）の「権限」セクションから各設定画面を開けます。

### 2. Notion 連携（任意）

1. [Notion Integrations](https://www.notion.so/my-integrations) でインテグレーションを作成
2. 対象データベースにインテグレーションを接続
3. 環境設定に **Token** と **Database ID** を入力

### 3. OpenAI API（任意）

環境設定に API Key を入力すると、要約の精度が向上します。

## 使い方

1. **Arc 等で Google Meet を開き、ブラウザを前面にする**
2. メニューバーから「文字起こしを開始」（または ⌘⇧S）
3. 自分の声 → 話者A、相手の声 → 話者B としてフローティングパネルに表示
4. 「停止する」で会議を保存・要約生成
5. 「履歴を開く」（⌘O）で過去の会議を確認

詳細は [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) を参照してください。

```bash
chmod +x scripts/*.sh
./scripts/build-release.sh
./scripts/create-dmg.sh
```

## ダウンロード版が開けない場合（Gatekeeper）

GitHub からダウンロードしたベータ版は、**Developer ID 署名・公証前**のため macOS に「開発元を確認できない」と表示されることがあります。

### 方法1: 右クリックで開く（推奨）

1. `Echo.app` を Applications にコピー
2. **右クリック（または Control+クリック）** → **「開く」**
3. ダイアログで再度 **「開く」**

2回目以降は通常どおり起動できます。

### 方法2: ターミナルで検疫属性を解除

```bash
xattr -cr /Applications/Echo.app
open /Applications/Echo.app
```

### 本番配布について

不特定多数への配布では **Apple Developer Program** への加入と **Developer ID 署名 + 公証** が必要です。手順は [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) を参照してください。

## ショートカット

| 操作 | ショートカット |
|------|---------------|
| 文字起こしの開始/停止 | ⌘⇧S |
| 履歴を開く | ⌘O |
| 環境設定 | ⌘, |

## ディレクトリ構成

```
echo/
├── Echo.xcodeproj
├── Echo/
│   ├── Services/          # 文字起こし・システム音声・Meet検知
│   ├── Views/
│   └── ...
└── docs/
    └── design-spec.md
```
