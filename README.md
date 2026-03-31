# 7Go — Apple Watch 振動通知アプリ

友達のボタンを押すと、相手の Apple Watch が振動するアプリ。
コンビニ休憩の誘い合いなど、シンプルな "サイン" 送信ユースケースを想定。

---

## アーキテクチャ

```
[送信者 iPhone 7Go アプリ]
  → HTTPS POST /signal
[Python バックエンド]
  → ntfy トピックへ publish
[ntfy サーバー]
  → プッシュ通知
[受信者 iPhone / Apple Watch]
  → 通知ハプティクス (振動)
```

**重要:** クロスユーザー通信は通知経由。`WatchConnectivity` は同一ユーザーの iPhone↔Watch 連携専用のため非使用。

---

## フォルダ構成

```
7Go/
├── 7Go.xcodeproj           # Xcode プロジェクト (xcodegen 生成)
├── project.yml              # XcodeGen 設定ソース
├── ios/
│   ├── Sources/
│   │   ├── SevenGoApp.swift     # アプリエントリポイント
│   │   ├── LoginView.swift      # ログイン画面
│   │   ├── HomeView.swift       # 友達一覧・シグナル送信
│   │   ├── FriendSearchView.swift # 友達検索
│   │   ├── SetupView.swift      # 設定画面
│   │   ├── UserSession.swift    # 認証セッション管理
│   │   ├── APIClient.swift      # API クライアント
│   │   └── Info.plist
│   ├── 7Go.entitlements         # Release用 (Sign in with Apple)
│   ├── 7GoDebug.entitlements    # Debug用 (空)
│   ├── PrivacyInfo.xcprivacy    # プライバシーマニフェスト
│   └── Assets.xcassets/
├── watch/
│   ├── Sources/
│   │   ├── ReceiverWatchApp.swift   # Watch アプリ + 通知デリゲート
│   │   ├── ContentView.swift        # Watch メイン画面
│   │   ├── NotificationView.swift   # 通知表示 UI
│   │   ├── NotificationPayload.swift # 通知パース
│   │   └── Info.plist
│   ├── PrivacyInfo.xcprivacy
│   └── Assets.xcassets/
└── server/
    └── server.py            # Python バックエンド (SQLite + ntfy)
```

---

## セットアップ

### 1. ntfy セットアップ (受信者側)

受信者ごとに秘密のトピック名を決める。

1. 受信者の iPhone に [ntfy アプリ](https://apps.apple.com/app/ntfy/id1625396347) をインストール
2. `ntfy` アプリでトピック名を購読 (例: `pulse-aya-xxxxxxxx`)
3. iPhone の設定 → 通知 → ntfy → 通知を許可
4. Watch アプリ → 通知 → ntfy → 通知をミラーリング (または個別許可)

### 2. contacts.json を編集

```json
[
  {
    "id": "aya",
    "displayName": "Aya",
    "note": "同僚",
    "ntfyTopic": "pulse-aya-ここを推測困難なランダム文字列に変える"
  }
]
```

トピック名は URL に含まれるため、推測されにくいランダム文字列を使うこと。

### 3. サーバー起動

```bash
cd server
python3 server.py
```

デフォルト: `http://127.0.0.1:8787`

実機 iPhone から接続する場合は Mac の IP アドレスで起動:

```bash
SIGNAL_HOST=0.0.0.0 python3 server.py
```

Mac の IP アドレス確認:

```bash
ipconfig getifaddr en0
```

---

## Xcode ビルド手順

### 前提条件

- Xcode がインストール済み
- iPhone 実機 (または シミュレータ)
- Apple Watch 実機 (または watchOS シミュレータ)
- Apple Developer アカウント (無料アカウントで実機ビルド可)

### ビルド手順

1. `7Go.xcodeproj` を開く

2. **Team 設定** (実機ビルド時のみ必要)
   - `7Go` ターゲット → Signing & Capabilities → Team を設定
   - `7GoWatch` ターゲット → Signing & Capabilities → Team を設定
   - Bundle Identifier が他と衝突する場合は変更する (例: `com.yourname.pulseping`)

3. **iPhone アプリをビルド**
   - スキーム: `7Go`
   - Run Destination: 自分の iPhone または iPhone シミュレータ
   - ▶ Run

4. **サーバー URL を変更 (実機の場合)**
   - `ios/Sources/SignalClient.swift` の `baseURL` を Mac の IP アドレスに変更
   - 例: `http://192.168.1.10:8787`

5. **Watch アプリをビルド** (Watch 通知テスト時)
   - スキーム: `7GoWatch`
   - Run Destination: Apple Watch
   - ▶ Run

### Apple Watch を Run Destination に表示させるには

- Mac の Wi-Fi を **ON** にする (Wi-Fi 経由でインストール)
- Apple Watch が iPhone と **ペアリング済み・近く**にある
- Watch の **開発者モードを ON**: Watch アプリ → 一般 → プライバシーとセキュリティ → 開発者モード

---

## 動作確認手順

### シミュレータで確認

1. `server.py` を起動 (`python3 server/server.py`)
2. iPhone シミュレータで `7Go` を起動
3. 連絡先を選んで "Send Tap" をタップ
4. ステータス欄に `Signal sent to ...` が表示されれば成功

### 実機で振動まで確認

1. 受信者の iPhone に ntfy アプリをインストール・トピック購読済み
2. サーバーを `SIGNAL_HOST=0.0.0.0` で起動
3. 送信者 iPhone で `baseURL` を Mac の IP に変更してビルド
4. "Send Tap" → 受信者 Apple Watch が振動

### Watch アプリのローカル振動テスト

- Watch に `7GoWatch` をインストール
- アプリを**前面**に表示した状態で "Play Local Haptic" ボタンをタップ
- 振動が発生すれば Watch 側のセットアップは正常

---

## API リファレンス

### GET /health

```
200 OK
{"ok": true}
```

### GET /contacts

```
200 OK
[{"id": "aya", "displayName": "Aya", "note": "同僚"}]
```

### POST /signal

```json
{
  "contactId": "aya",
  "senderName": "Taro",
  "message": "コンビニ行かない？"
}
```

```json
{"delivered": true, "detail": "Signal sent to Aya."}
```

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| Watch が Run Destination に出ない | Wi-Fi OFF / 開発者モード未設定 | Mac Wi-Fi ON, Watch 開発者モード有効化 |
| ビルドエラー "No Team" | Team 未設定 | 全ターゲットに同じ Team を設定 |
| `Signal sent to ...` は出るが振動しない | ntfy 通知設定 | ntfy → Watch 通知のミラーリング設定を確認 |
| API 接続タイムアウト (実機) | baseURL が 127.0.0.1 のまま | Mac の IP アドレスに変更 |
| ntfy から通知が来ない | トピック名不一致 | `contacts.json` の `ntfyTopic` と ntfy アプリの購読トピックを一致させる |

---

## 本番移行ポイント

| 項目 | MVP (現状) | 本番 |
|------|-----------|------|
| 通知経路 | ntfy (サードパーティ) | APNs (Apple Push Notification service) |
| 認証 | なし | JWT / OAuth |
| デバイストークン管理 | ntfy が担当 | サーバーで管理 |
| HTTP | ATS 例外で許可 | HTTPS 必須、ATS 例外削除 |
| トピック秘匿 | URL パラメータ (ntfy) | サーバー側で管理 |

---

## XcodeGen でプロジェクトを再生成する場合

```bash
cd 7Go
xcodegen generate
```
