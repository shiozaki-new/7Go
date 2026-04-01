# 7Go - AI向け開発メモ

## プロジェクト概要
Apple Watch同士で友達にバイブレーション（シグナル）を送り合うアプリ。
iOS親アプリ + watchOS子アプリ + Pythonバックエンド（SQLite + ntfy通知）。

## アーキテクチャ
```
ios/Sources/       → iOS親アプリ（SwiftUI）
watch/Sources/     → watchOS受信アプリ（SwiftUI）
server/server.py   → Pythonバックエンド（HTTPサーバー, SQLite, ntfy）
project.yml        → XcodeGen定義（xcodeproj は生成物）
```

## ビルド手順
```bash
# 1. xcode-select が Xcode を指していることを確認
xcode-select -p  # → /Applications/Xcode.app/Contents/Developer

# 2. プロジェクト生成
cd /Users/airm3/7Go
xcodegen generate

# 3. ビルド（コマンドライン）
xcodebuild -scheme 7Go -destination 'generic/platform=iOS' build
xcodebuild -scheme 7GoWatch -destination 'generic/platform=watchOS' build
```

## 署名情報
- **Team ID**: M878XBQ25U
- **Bundle ID (iOS)**: com.macminim4pro.sevengo
- **Bundle ID (Watch)**: com.macminim4pro.sevengo.watchkitapp
- **証明書**: Apple Development: skstudio8004430@gmail.com (7D3R5VYL4J)
- **アカウント種別**: Apple Developer Program（有料・加入済み）

## 現在の未解決問題

### 1. サーバーのクラウドデプロイ
**現状**: `server/server.py` がまだクラウドにデプロイされていない。
**対応**:
- `render.yaml` を使って Render.com にデプロイ
- デプロイ後、`project.yml` の `SERVER_URL` をデプロイ先URLに書き換え
- `xcodegen generate` を再実行

### 2. App Store 提出
**現状**: コード準備完了。提出は手動で行う必要あり。
**手順**:
1. サーバーをデプロイし SERVER_URL を更新
2. Xcode で Archive → App Store Connect にアップロード
3. App Store Connect でメタデータ・スクリーンショットを登録
4. Review に提出

## 完了済み修正

### 2026-04-01
- [x] Apple Developer Program 加入完了
- [x] Debug entitlements に Sign in with Apple を追加
- [x] サーバーのクラウドデプロイ準備（Dockerfile, render.yaml）
- [x] DB パスの環境変数対応（DB_PATH）
- [x] App Store メタデータ作成（docs/appstore-metadata.md）

### 2026-03-31
- [x] `xcode-select` を Xcode に切り替え（watchOSビルド不可 → 解消）
- [x] `DEVELOPMENT_TEAM` を project.yml に追加（署名エラー → 解消）
- [x] Debug/Release で entitlements を分離（Personal Team対応）
- [x] `SERVER_URL` を Info.plist 経由で Config別に設定
- [x] APIClient にエラーハンドリング・ATS ローカルネットワーク例外追加
- [x] Debug ビルドで HTTP 接続許可（HTTPS強制は Release のみ）
- [x] Interface Orientations 警告修正
- [x] Watch app ソース整理（ContentView, NotificationView, NotificationPayload 分離）

## 重要な注意事項
- `7Go.xcodeproj` は XcodeGen の生成物。**直接編集しない**。`project.yml` を編集して `xcodegen generate` を実行。
- `ios/7GoDebug.entitlements` と `ios/7Go.entitlements` の両方に Sign in with Apple が設定済み。
- サーバーは `0.0.0.0:8787` でリッスンするが、macOS ファイアウォールが「すべての受信接続をブロック」状態のため外部からアクセス不可。
