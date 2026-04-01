# App Store リリース手順書（7Go）

> **対象**: AI（Claude / Codex）および開発者本人
> **最終更新**: 2026-04-01
> **実績**: この手順で 7Go v1.0.0 を審査提出済み

---

## 前提条件

| 項目 | 必須 | 確認方法 |
|------|------|---------|
| Apple Developer Program（有料・年12,800円） | ✅ | https://developer.apple.com/account |
| Xcode インストール済み | ✅ | `xcode-select -p` |
| XcodeGen インストール済み | ✅ | `xcodegen --version` |
| GitHub リポジトリ | ✅ | `git remote -v` |
| サーバーがクラウドにデプロイ済み | ✅ | `curl https://sevengo.onrender.com/health` |

---

## 全体フロー（6ステップ）

```
1. サーバーデプロイ          ← コマンドで可能
2. project.yml 更新          ← コマンドで可能
3. Archive & アップロード    ← コマンドで可能
4. App Store Connect 設定    ← ブラウザ操作が必要（⚠️ ここが最難関）
5. 審査へ提出                ← ブラウザでボタン1つ
6. 審査通過 → 公開           ← 待つだけ（通常24〜48時間）
```

---

## Step 1: サーバーデプロイ（Render.com）

### コマンドでできること
```bash
# render.yaml がリポジトリに含まれていることを確認
cat render.yaml

# リポジトリが Public であることを確認（Render が参照するため）
gh repo edit <owner>/<repo> --visibility public --accept-visibility-change-consequences
```

### ブラウザで必要な操作
1. https://render.com → GitHub でサインアップ
2. **New → Web Service**（⚠️ Blueprint ではない。render.yaml があっても Web Service を選ぶ方が確実）
3. リポジトリを選択（Private の場合は Public にするか、GitHub連携で権限付与）
4. 設定値:

| 設定 | 値 |
|------|-----|
| Name | `7go-server` |
| Language | **Python** |
| Region | **Singapore** |
| Root Directory | `server` |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `python3 server.py` |
| Instance Type | **Free** ($0) |

5. **Create Web Service** → デプロイ完了まで1〜2分
6. ログに `Detected a new open port HTTP:8787` が出たら成功
7. URL（例: `https://sevengo.onrender.com`）をメモ

### デプロイ確認
```bash
curl -s https://sevengo.onrender.com/health
# → {"ok": true} なら成功
```

---

## Step 2: project.yml 更新

```bash
# SERVER_URL をデプロイ先に変更（Debug / Release 両方）
# project.yml の以下を書き換え:
#   Debug:  SERVER_URL: "https://sevengo.onrender.com"
#   Release: SERVER_URL: "https://sevengo.onrender.com"
# schemes の environmentVariables も同様

# Xcode プロジェクト再生成
xcodegen generate
```

---

## Step 3: Archive & App Store Connect へアップロード

### 全部コマンドで可能
```bash
# 1. Archive 作成
xcodebuild -scheme 7Go \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath ./build/7Go.xcarchive \
  archive

# 2. ExportOptions.plist 作成
cat > ./build/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>M878XBQ25U</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

# 3. App Store Connect にアップロード
#    ⚠️ -allowProvisioningUpdates が必須（プロファイル自動生成）
xcodebuild -exportArchive \
  -archivePath ./build/7Go.xcarchive \
  -exportOptionsPlist ./build/ExportOptions.plist \
  -exportPath ./build/export \
  -allowProvisioningUpdates

# "EXPORT SUCCEEDED" が出たら成功
# ⚠️ App Store Connect にアプリが未登録だと失敗する（Step 4 を先にやる）
```

### よくあるエラー

| エラー | 原因 | 対処 |
|--------|------|------|
| `No profiles for 'com.macminim4pro.sevengo'` | プロビジョニングプロファイルがない | `-allowProvisioningUpdates` を付ける |
| `Error Downloading App Information` | App Store Connect にアプリ未登録 | **Step 4 のアプリ作成を先にやる** |
| `SERVER_URL must use HTTPS` | Release の SERVER_URL が http | project.yml を https に修正 |

---

## Step 4: App Store Connect 設定（⚠️ 最難関・ブラウザ必須）

> **AI への注意**: このステップはブラウザ操作が必要。
> ユーザーにスクショを送ってもらいながら1つずつ進めること。
> 入力値はすべてコピペ可能な形で提示すること。

### 4-1. アプリ作成

1. https://appstoreconnect.apple.com にアクセス
2. **「アプリ」** → 左上の **「+」** → **「新規App」**
3. 入力値:

| 項目 | 値 |
|------|-----|
| プラットフォーム | **iOS**（watchOS アプリは iOS に含まれる） |
| 名前 | `7Go` |
| プライマリ言語 | **日本語** |
| バンドルID | `com.macminim4pro.sevengo` を選択 |
| SKU | `sevengo` |
| ユーザアクセス | **アクセス制限なし** |

4. **「作成」**

### 4-2. 必須入力項目一覧（これを埋めないと審査提出できない）

> **⚠️ 重要**: 以下をすべて埋めないと「審査用に追加」ボタンが押せない。
> エラーメッセージは赤いバナーで表示される。1つずつ潰していくこと。

#### A. 「1.0 提出準備中」ページ（メイン）

| 項目 | 場所 | 入力値 |
|------|------|--------|
| **iPhone スクリーンショット** | プレビューとスクリーンショット → iPhone タブ | 6.5インチ (1284×2778) の PNG |
| **iPad スクリーンショット** | プレビューとスクリーンショット → iPad タブ | 13インチの PNG |
| **Apple Watch スクリーンショット** | プレビューとスクリーンショット → Apple Watch タブ | Watch の PNG |
| **概要** | 下にスクロール | アプリの説明文 |
| **キーワード** | 概要の下 | カンマ区切り100文字以内 |
| **サポートURL** | キーワードの下 | `https://github.com/shiozaki-new/7Go` |
| **著作権** | さらに下 | `2026 EISUKE SHIOZAKI` |
| **ビルド** | 「ビルド」セクション → 「ビルドを追加」 | アップロード済みビルドを選択 |
| **サインイン情報** | App Review セクション | チェックを**外す**（Sign in with Apple のため不要） |
| **連絡先情報** | App Review セクション | 姓・名・電話番号・メール |

#### B. 「アプリ情報」ページ（左メニュー）

| 項目 | 入力値 |
|------|--------|
| カテゴリ（プライマリ） | **ソーシャルネットワーキング** |
| コンテンツ配信権 | **いいえ** |
| 年齢制限 | すべて「いいえ」→ **4+** |

#### C. 「アプリのプライバシー」ページ（左メニュー）

| 項目 | 入力値 |
|------|--------|
| プライバシーポリシーURL | `https://sevengo.onrender.com/privacy` |
| データ収集 | 「はじめに」→ **はい、収集する** |
| データタイプ | **連絡先情報 → 名前** のみチェック |
| 名前の用途 | **アプリの機能** |
| ユーザにリンク | **はい** |
| トラッキング目的 | **いいえ** |
| 最後に **「公開」** ボタン | 押す |

> ⚠️ プライバシーポリシーURL は「日本語」ローカライズにも設定が必要。
> 「編集」を押して保存すること。

#### D. 「価格および配信状況」ページ（左メニュー）

| 項目 | 入力値 |
|------|--------|
| 価格 | **無料** |

### 4-3. スクリーンショット生成（コマンド）

```bash
# iPhone 6.5インチ（iPhone 16 Pro Max）
xcrun simctl boot <iPhone16ProMax_UDID>
xcodebuild -scheme 7Go -destination 'platform=iOS Simulator,id=<UDID>' -configuration Release build
xcrun simctl install <UDID> <path_to_app>
xcrun simctl launch <UDID> com.macminim4pro.sevengo
sleep 3
xcrun simctl io <UDID> screenshot screenshot_iphone.png
# 6.5インチサイズにリサイズ
sips -z 2778 1284 screenshot_iphone.png --out iphone_6_5.png

# iPad 13インチ
xcrun simctl boot <iPadPro13_UDID>
# 同様にビルド → インストール → 起動 → スクリーンショット

# Apple Watch
xcrun simctl boot <WatchSeries11_UDID>
xcodebuild -scheme 7GoWatch -destination 'platform=watchOS Simulator,id=<UDID>' -configuration Release build
xcrun simctl install <UDID> <path_to_watch_app>
xcrun simctl launch <UDID> com.macminim4pro.sevengo.watchkitapp
# ⚠️ 初回起動時に通知許可ダイアログが出る
# → Simulator アプリを開いてユーザーに「許可」を押してもらう必要がある
sleep 5
xcrun simctl io <UDID> screenshot watch_screenshot.png
```

> ⚠️ Watch の通知許可ダイアログは `simctl` では自動タップできない。
> `open -a Simulator` で Simulator を表示してユーザーに手動で押してもらうこと。

---

## Step 5: 審査へ提出

App Store Connect で全項目が緑になったら:
1. **「審査用に追加」** ボタンを押す
2. 右側に「提出物の下書き」パネルが表示される
3. **「審査へ提出」** を押す

---

## Step 6: 審査通過 → 公開

- 通常 **24〜48時間** で審査結果が届く
- メールで通知される
- 「承認済み」になったら App Store に公開される
- リジェクトされた場合はメールに理由が書いてあるので対応

---

## トラブルシューティング

### 「審査用に追加できません」のエラー一覧

| エラーメッセージ | 対処 |
|------------------|------|
| 日本語 - 概要 - 必須です | 「1.0 提出準備中」→ 下にスクロール → 概要を入力 |
| 日本語 - キーワード - 必須です | 同上 → キーワードを入力 |
| 日本語 - サポートURL - 必須です | 同上 → サポートURLを入力 |
| プライバシーポリシーURL - 必須です | 「アプリのプライバシー」→「編集」→ URL入力 → 保存 |
| iPadスクリーンショット必要 | iPad タブにスクリーンショットをドラッグ |
| Apple Watchスクリーンショット必要 | Apple Watch タブにスクリーンショットをドラッグ |
| ビルドを選択する必要があります | 「ビルドを追加」→ ビルド選択（処理中なら5〜10分待つ） |
| 著作権 - 必須です | 下にスクロール → `2026 EISUKE SHIOZAKI` |
| 価格帯を選択する必要があります | 左メニュー「価格および配信状況」→ 無料 |
| ユーザ名 - 必須です | サインイン情報のチェックを外す |
| 連絡先セクション | 姓・名・電話番号・メールを入力 |

### Render デプロイの注意

- Free プランは **15分間アクセスがないとスリープ** → 次のリクエストに50秒かかる
- 本番運用では Starter プラン（$7/月）推奨
- DB は Free プランでは永続ディスク不可 → サーバー再起動でデータ消失の可能性あり

---

## 7Go 固有の情報

| 項目 | 値 |
|------|-----|
| Team ID | `M878XBQ25U` |
| Bundle ID (iOS) | `com.macminim4pro.sevengo` |
| Bundle ID (Watch) | `com.macminim4pro.sevengo.watchkitapp` |
| サーバーURL | `https://sevengo.onrender.com` |
| プライバシーポリシー | `https://sevengo.onrender.com/privacy` |
| GitHub | `https://github.com/shiozaki-new/7Go` |
| Apple ID (App Store Connect) | `6761447247` |
