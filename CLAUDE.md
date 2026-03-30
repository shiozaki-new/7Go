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
- **アカウント種別**: Personal Team（無料）

## 現在の未解決問題

### 1. ログインが動かない
**原因**: 2つの認証方法どちらも失敗する状態。
- **Sign in with Apple**: Personal Team（無料）では `com.apple.developer.applesignin` エンタイトルメントが使えない。有料 Apple Developer Program（年12,800円）が必要。
- **ローカルデバッグログイン**: サーバー（`http://192.168.1.7:8787`）に接続できないため失敗。

**対応方針（どちらかを選択）:**

#### 方針A: サーバーをクラウドにデプロイ（推奨）
- `server/server.py` を Render / Railway / fly.io 等にデプロイ
- `project.yml` の `SERVER_URL` をデプロイ先URLに変更
- ログインは「ローカルデバッグで入る」ボタンで機能する（サーバーにさえ繋がれば動く）
- Sign in with Apple は有料アカウント取得後に有効化

#### 方針B: macOS ファイアウォール設定変更
- システム設定 → ネットワーク → ファイアウォール → オプション → 「すべての受信接続をブロック」をオフ
- `python3 server/server.py` でローカルサーバー起動
- iPhoneとMacが同じWi-Fiにいれば `http://192.168.1.7:8787` で接続可能

### 2. 友達への配布
**現状**: Personal Team ではTestFlight配布不可。
**対応**:
- 有料 Apple Developer Program に加入
- Sign in with Apple エンタイトルメントを Debug entitlements にも追加
- TestFlight で配布

### 3. SERVER_URL がローカルIP固定
**現状**: `project.yml` の Debug設定が `http://192.168.1.7:8787` にハードコード。
**対応**: クラウドデプロイ後、HTTPS URLに書き換える。変更後は `xcodegen generate` を再実行。

## 完了済み修正（2026-03-31）
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
- `ios/7GoDebug.entitlements` は空（Personal Team用）。`ios/7Go.entitlements` は Release用（Sign in with Apple + APNs）。
- サーバーは `0.0.0.0:8787` でリッスンするが、macOS ファイアウォールが「すべての受信接続をブロック」状態のため外部からアクセス不可。
