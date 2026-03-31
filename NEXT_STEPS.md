# 7Go — App Store公開までのやることリスト

## 現在の状態
- ✅ コード完成（iOS + watchOS ビルド成功、warning 0）
- ✅ GitHub にプッシュ済み
- ⬜ 以下の作業が残っている

---

## Step 1: Apple Developer Program に登録（あなたの作業）

1. https://developer.apple.com/programs/ にアクセス
2. Apple ID でサインイン
3. 個人（Individual）で登録
4. ¥15,800 支払い
5. 審査完了まで最大48時間待つ

**完了したら Step 2 へ**

---

## Step 2: サーバーをデプロイ（Render + Turso）

### 2-1. Render アカウント作成
1. https://render.com にアクセス
2. GitHub アカウントで登録
3. 「New Web Service」で `server/server.py` をデプロイ

### 2-2. Turso アカウント作成（クラウドDB）
1. https://turso.tech にアクセス
2. 無料プランで登録
3. データベースを作成
4. `server.py` の接続先を Turso に変更

### 2-3. SERVER_URL を更新
```bash
# project.yml の Release 設定を変更
# 変更前
SERVER_URL: "https://your-server.example.com"
# 変更後
SERVER_URL: "https://your-app-name.onrender.com"

# 変更後に再生成
xcodegen generate
```

---

## Step 3: GitHub Pages でプライバシーポリシーを公開

1. GitHub リポジトリの Settings → Pages → Source を main に設定
2. `docs/` フォルダに以下を作成：
   - `docs/privacy.html` — プライバシーポリシー
   - `docs/terms.html` — 利用規約
   - `docs/support.html` — サポートページ
3. 公開URL例: `https://shiozaki-new.github.io/7Go/privacy.html`
4. `ios/Sources/SetupView.swift` の URL をこれに差し替え

---

## Step 4: Sign in with Apple を有効化

1. https://developer.apple.com/account にアクセス
2. Certificates, Identifiers & Profiles → Identifiers
3. `com.macminim4pro.sevengo` を選択
4. 「Sign In with Apple」を有効化
5. `ios/7GoDebug.entitlements` にも追加：
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

---

## Step 5: APNs 証明書を設定

1. Apple Developer → Certificates → 「+」
2. 「Apple Push Notification service SSL」を選択
3. App ID: `com.macminim4pro.sevengo` を選択
4. CSR をアップロードして証明書を取得
5. サーバー（Render）に証明書を設定

---

## Step 6: TestFlight でテスト

1. Xcode → Product → Archive
2. Organizer → Distribute App → App Store Connect
3. App Store Connect でテスターを招待
4. 友達に TestFlight リンクを送る
5. バグ出し・修正

---

## Step 7: App Store に提出

1. App Store Connect にログイン
2. 「マイ App」→「+」→ 新規 App
3. 必要情報を入力：
   - App 名: **7Go**
   - バンドル ID: `com.macminim4pro.sevengo`
   - プライマリ言語: 日本語
   - カテゴリ: ソーシャルネットワーキング
   - 価格: 無料（App内課金あり）
4. スクリーンショットをアップロード（6.7インチ + 5.5インチ）
5. プライバシーポリシー URL を入力
6. サポート URL を入力
7. 審査に提出

---

## Step 8: Pro課金機能を追加（任意・後でOK）

- StoreKit 2 でアプリ内課金を実装
- 7Go Pro（¥160 買い切り）
  - シグナル全種類解放
  - 友達無制限
  - カスタムシグナル作成
  - 送信履歴

---

## ローカルでビルドする手順

```bash
# リポジトリをクローン
git clone https://github.com/shiozaki-new/7Go.git
cd 7Go

# ブランチ切り替え（PRマージ前の場合）
git checkout claude/vibrant-heyrovsky

# プロジェクト生成
xcodegen generate

# ビルド
xcodebuild -scheme 7Go -destination 'generic/platform=iOS' build -allowProvisioningUpdates
xcodebuild -scheme 7GoWatch -destination 'generic/platform=watchOS' build -allowProvisioningUpdates
```

---

## 費用まとめ

| 項目 | 費用 |
|------|------|
| Apple Developer Program | ¥15,800/年 |
| Render（サーバー） | ¥0（無料枠） |
| Turso（データベース） | ¥0（無料枠） |
| GitHub Pages | ¥0 |
| APNs | ¥0（Developer料金に含む） |
| **合計** | **¥15,800/年** |
