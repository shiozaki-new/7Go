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

### ローカルビルド（確認用）
```bash
# 1. xcode-select が Xcode を指していることを確認
xcode-select -p  # → /Applications/Xcode.app/Contents/Developer

# 2. プロジェクト生成
cd /Users/macminim4pro/7Go
xcodegen generate

# 3. ビルド（コマンドライン）
xcodebuild -scheme 7Go -destination 'generic/platform=iOS' build
xcodebuild -scheme 7GoWatch -destination 'generic/platform=watchOS' build
```

### TestFlight配布（重要：必ずこの手順で）

⚠️ **注意**: 必ず `/Users/macminim4pro/7Go`（メインリポジトリ）で実行すること。
worktree（`.claude/worktrees/`配下）で編集した場合は、**先にmainにマージしてから**ビルドする。

```bash
# 0. worktreeで作業した場合：変更をmainにマージ
git push origin <ブランチ名>
gh pr create --base main ...
gh pr merge <PR番号> --merge
cd /Users/macminim4pro/7Go && git pull origin main

# 1. バージョン更新（3箇所すべて更新すること！）
#    - project.yml   → CFBundleShortVersionString, CFBundleVersion（iOS・Watch両方）
#    - ios/Sources/Info.plist → CFBundleShortVersionString, CFBundleVersion
#    - watch/Sources/Info.plist → CFBundleShortVersionString, CFBundleVersion
#    ※ project.yml だけでなく Info.plist も直接編集が必要（XcodeGenがplistのハードコード値を上書きしない）

# 2. プロジェクト生成
cd /Users/macminim4pro/7Go
xcodegen generate

# 3. アーカイブ
xcodebuild -scheme 7Go \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  archive \
  -archivePath ./build/7Go.xcarchive \
  DEVELOPMENT_TEAM=M878XBQ25U \
  CODE_SIGN_STYLE=Automatic

# 4. App Store Connect にアップロード
xcodebuild -exportArchive \
  -archivePath ./build/7Go.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ./build/ExportOptions.plist

# 5. GitHubにもpush
git add -A && git commit -m "chore: バージョンをX.Y.Zに更新"
git push origin main
```

### ExportOptions.plist（`build/ExportOptions.plist`に配置済み）
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>M878XBQ25U</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>upload</string>
</dict>
</plist>
```

### よくあるミス
- ❌ worktreeでコード変更 → mainにマージせずにビルド → 変更が反映されない
- ❌ project.yml のバージョンだけ変更 → Info.plistのハードコード値が古いまま
- ❌ ビルド番号を上げ忘れ → App Store Connectが同一ビルドとして拒否

## 署名情報
- **Team ID**: M878XBQ25U
- **Bundle ID (iOS)**: com.macminim4pro.sevengo
- **Bundle ID (Watch)**: com.macminim4pro.sevengo.watchkitapp
- **証明書**: Apple Development: skstudio8004430@gmail.com (7D3R5VYL4J)
- **アカウント種別**: Apple Developer Program（有料・加入済み）

## 現在の状態

### サーバー
- **デプロイ済み**: https://sevengo.onrender.com（Render.com 無料プラン）
- 無料プランのため15分間アクセスがないとスリープ → 初回リクエストで502が出る可能性あり
- APIClientに502/503の自動リトライ（最大3回）を実装済み

### TestFlight
- **内部テスター**で配布中（審査なし・即配布）
- App Store Connect → TestFlight → 社内テスターグループで管理

### Watch連携
- iPhoneでログイン → WatchConnectivity でセッション自動同期
- Watchで友達一覧表示・シグナル送信が可能

## 完了済み修正

### 2026-04-02
- [x] TestFlight 内部テスター配布開始
- [x] Apple Watch独立操作（WatchConnectivityでセッション同期）
- [x] APIClientに502/503自動リトライ追加
- [x] 設定画面からntfy関連項目を削除
- [x] バージョン1.1.0に更新

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
