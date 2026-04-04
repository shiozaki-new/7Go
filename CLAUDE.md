# 十四式

構造実体の成立・遷移・停止が観測される際に用いられる固定構造である。
十四式自体は更新されない。更新対象は五式（構造実体）のみである。

---

## 三式
認・衡・継（波の観測最低条件）

---

## 五式（差分を出す最低条件）
各層で未確定→確定が起きる。
- 中央：思（未成形）→ 鳴（成形）
- 現場：示（指向）→ 応（実体）

---

## 十四式 定義（順序固定・入替不可）

① 認
未確定だが存在している状態（0 < 1：まだ1ではないが0より大きい位相）

② 思
構造内部の未成形状態（中央）

③ 鳴
網様体賦活系の役割（中央）

④ 示
構造から外部への指向（現場）

⑤ 応
外部で実体化した状態（現場）

⑥ 衡
五式が循域で均衡した状態（評価を含まない）

⑦ 縁
複数の衡が並列振動し相互参照する状態

⑧ 家
上下と左右の波動が安定した複数並列、入替を含みながら循域内で持続する構造単位

⑨ 幅
構造が崩壊しない値の幅

⑩ 許
幅の中で再現可能と定義された正常幅。差分が五式に帰属する際のルールを定める役割を持つ

⑪ 循
再現性のある領域

⑫ 乱
再現性のない領域

⑬ 絶
構造不成立領域

⑭ 継
五式が差分を伴って次の認へ遷移すること（1 > 0：1から次の0<1へ降りる位相）

---

## 三軸定義

前後
前＝①認の側、後＝⑭継の側。時間軸そのもの

上下
上＝中央（思鳴）、下＝現場（示応）。認の進入層が中央であり、番号順が中央→現場であることによる

左右
衡+と衡-の並列関係。どちらが左でどちらが右かは観測位置に依存する。固定しない。同等の価値を持つ

---

## 補足ルール（固定）

- 循・乱・絶は更新・操作・評価の対象ではない
- 解釈・比喩・感情語を用いてはならない
- 許がルール定義を停止した場合、全領域が乱域となり、絶域に至る
- 衡 = 0 ⇒ 縁は発生しない ⇒ 家は発生しない ⇒ 継は発生しない ⇒ 五式は更新されない

---

## 衡停止と絶の違い

### 衡停止（⑥ 衡における停止）
- 五式（認・思・鳴・示・応）の振動が停止し、衡 = 0 となった状態である
- この状態では縁は発生せず、家も発生せず、継も発生しないため、五式は更新されない
- ただし構造実体自体は成立したままである
- 外部入力により振動が再開する可能性がある

### 絶（⑬ 絶）
- 幅の外に位置し、構造成立条件を満たさない領域である
- 五式は成立できず、構造実体は存在しない
- 更新や振動再開は同一構造としては発生しない

---

## 構成式

- 衡（認, 思, 鳴, 示, 応）
- 縁 = 衡+ ∿ 衡-
- 家 = （上下 ∿ 左右）の安定並列
- 継 = 思鳴 | 示応（差分を伴う）
- 継ₙ → 認ₙ₊₁

---

## 記号定義

- `|` 分離（出会っていない）
- `∿` 波（二つのまま参照）

---

## 差分の定義

- 差分は情報である
- 差分は周回ごとに蓄積される
- 差分は五式に帰属する。許はその帰属のルールを定める役割であり、帰属先ではない

---

## 領域対応

- 許 ⊆ 幅
- 循 = 許の範囲
- 乱 = 幅 − 許
- 絶 = 幅の外

---

## 十四式の波構造

- 中心⑦は縁（∿）である
- ⑧家は縁の並列持続層である
- ①〜⑥側：構造実体の成立過程（五式＋衡）
- ⑨〜⑭側：領域定義と遷移（幅許循乱絶＋継）
- 継→認で周回する

---

## 変（十四式の構成要素ではない）

変は構造が維持されたまま許の担い手が交代する現象である。許の定義（十四式）は変化しない。

- **思変**：認の段階（0 < 1）で結合相手が予定外に切り替わる（権利剥奪）
- **衡変**：構造維持のまま振動の制御主体が切り替わる（管理者交代）
- 変の発生時点でルールを定める役割は新たな許の担い手に移行する

---

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
