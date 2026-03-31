# 7Go — Apple Watch バイブレーション通知アプリ

友達にワンタップでシグナルを送ると、相手の Apple Watch が振動するアプリ。

---

## アーキテクチャ

```
[送信者 iPhone 7Go アプリ]
  → HTTPS POST /signal
[Python バックエンド (Render)]
  → APNs / ntfy
[受信者 iPhone 7Go アプリ]
  → WatchConnectivity
[受信者 Apple Watch]
  → ハプティクス (振動)
```

---

## フォルダ構成

```
7Go/
├── 7Go.xcodeproj           # Xcode プロジェクト (xcodegen 生成)
├── project.yml              # XcodeGen 設定ソース
├── ios/Sources/             # iPhone アプリ
│   ├── SevenGoApp.swift     # App エントリポイント
│   ├── UserSession.swift    # 認証・セッション管理 (Keychain)
│   ├── APIClient.swift      # API クライアント
│   ├── NotificationManager.swift  # APNs・通知管理
│   ├── WatchConnectivityManager.swift  # Watch 連携
│   ├── KeychainHelper.swift # セキュアデータ保存
│   ├── OnboardingView.swift # 初回オンボーディング
│   ├── LoginView.swift      # ログイン画面
│   ├── HomeView.swift       # メイン画面 (友達一覧・シグナル送信)
│   ├── FriendSearchView.swift  # 友達検索・追加
│   ├── SetupView.swift      # 設定画面
│   └── Info.plist
├── watch/Sources/           # Apple Watch アプリ
│   ├── ReceiverWatchApp.swift
│   ├── ContentView.swift
│   ├── NotificationView.swift
│   ├── NotificationPayload.swift
│   └── WatchConnectivityManager.swift
└── server/
    └── server.py            # Python バックエンド
```

---

## ビルド手順

### 前提条件

- Xcode (xcode-select が Xcode を指していること)
- XcodeGen (`brew install xcodegen`)
- Apple Developer Program (App Store 配信時)

### ビルド

```bash
cd 7Go
xcodegen generate
xcodebuild -scheme 7Go -destination 'generic/platform=iOS' build -allowProvisioningUpdates
xcodebuild -scheme 7GoWatch -destination 'generic/platform=watchOS' build -allowProvisioningUpdates
```

---

## サーバー起動 (ローカル開発)

```bash
cd server
python3 server.py
```

デフォルト: `http://0.0.0.0:8787`

---

## API エンドポイント

| メソッド | パス | 説明 |
|---------|------|------|
| GET | /health | ヘルスチェック |
| POST | /register | ユーザー登録 |
| GET | /users/search?q=名前 | ユーザー検索 |
| GET | /friends | 友達一覧取得 |
| POST | /friends/add | 友達追加 |
| DELETE | /friends/:id | 友達削除 |
| POST | /signal | シグナル送信 |
| POST | /device-token | デバイストークン登録 |

---

## セキュリティ

- セッショントークンは Keychain に保存
- Release ビルドでは HTTPS を強制
- サーバー側でレート制限・入力サニタイズ実装済み
- SQLインジェクション対策済み (LIKE エスケープ)

---

## 署名情報

- **Team ID**: M878XBQ25U
- **Bundle ID (iOS)**: com.macminim4pro.sevengo
- **Bundle ID (Watch)**: com.macminim4pro.sevengo.watchkitapp

---

## XcodeGen でプロジェクトを再生成

```bash
xcodegen generate
```

`7Go.xcodeproj` は生成物。直接編集しないこと。
