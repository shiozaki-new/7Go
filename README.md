# 7Go4

Apple Watch を中心に、`振動 + 絵文字` を最短で届けるためのポケベル型アプリです。  
初版は `1対1`、`6桁ペアコード`、`9個の固定絵文字`、`iPhone / Watch の両方から送信` を前提にしています。

## 現在の実装方針

- 認証: `Sign in with Apple`
- ペアリング: `6桁コード`
- 送信内容: `🏪 ☕️ 🍽️ 🚻 🏠 🏢 🏫 🤫 🚑`
- 受信: `Apple Watch 主体 + iPhone は保険`
- 配信経路:
  `iPhone / Watch app -> 7Go4 server -> APNs -> recipient watch / iPhone`
- 補助経路:
  アプリ前面時の取りこぼし対策として `/signals/pending` をポーリング

## リポジトリ構成

```text
7Go4/
├── ios/                     # iPhone app
├── watch/                   # Apple Watch app
├── server/                  # Python backend
├── docs/                    # 設計メモ
├── project.yml              # XcodeGen source
└── 7Go4.xcodeproj/          # generated Xcode project
```

## サーバー機能

`server/server.py` は以下を扱います。

- ユーザー登録とセッション発行
- 6桁ペアコードの発行と交換
- ペア一覧の取得
- 絵文字シグナルの保存
- 最新100件の未読保留
- APNs 用デバイストークン登録
- APNs への通知送信

## 必要な環境変数

最低限:

```bash
SIGNAL_HOST=0.0.0.0
SIGNAL_PORT=8787
```

Turso を使う場合:

```bash
TURSO_URL=libsql://...
TURSO_TOKEN=...
```

APNs を有効にする場合:

```bash
APNS_KEY_ID=...
APNS_TEAM_ID=...
APNS_PRIVATE_KEY_PATH=/absolute/path/AuthKey_XXXX.p8
APNS_USE_SANDBOX=1
```

`APNS_PRIVATE_KEY` に秘密鍵本文を直接入れることもできます。  
どちらも未設定なら、サーバーは起動しますが push 配信は無効です。

## ローカル起動

```bash
cd "/Users/siojakieiseuke/Library/Mobile Documents/com~apple~CloudDocs/7Go4/server"
python3 server.py
```

ヘルスチェック:

```bash
curl http://127.0.0.1:8787/health
```

## iPhone / Watch 側の要点

- ログイン後に push token をサーバー登録する
- iPhone は `6桁コード` を表示し、相手コードを入力できる
- Watch は iPhone からセッション同期を受ける
- Watch / iPhone ともに `9絵文字` を送信できる
- Watch 通知では `送信者名 + 絵文字` を表示する

## 重要な制約

- `アプリが閉じている状態での完全な連続ライブ振動` は watchOS の制約で保証できません
- 閉じた状態では `1送信 = 1即時通知` を最優先にしています
- `長押しで連続送信` や `ライブ振動` は前面実行時に拡張する想定です

## TestFlight までの残タスク

- Apple Developer 側で Push Notifications capability を有効化
- 必要なら Time Sensitive Notifications capability を有効化
- APNs 鍵をサーバーに配置
- 実機で `送信タップ -> Watch振動` の計測
- 必要に応じて Watch 前面時のライブ振動 UI を追加
