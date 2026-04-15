# 7Go4 Architecture

## Goal

`7Go4` は、Apple Watch を主役にした `ポケベル型触覚コミュニケーション` を目指す。  
初版の最重要要件は以下。

- 閉じた状態でも、できるだけ最速で Apple Watch を振動させる
- 送る内容は `振動 + 絵文字1つ`
- 相手追加は `6桁コード`
- 初版は `1対1`
- iPhone / Watch の両方から送信する

## Current MVP

### User flow

1. iPhone で `Sign in with Apple`
2. 自分の `6桁コード` を表示
3. 相手の `6桁コード` を入力して相互接続
4. 9個の固定絵文字から1つを送信
5. サーバーがシグナルを保存し、登録済みの Watch / iPhone に APNs を送る
6. 相手の Apple Watch に `送信者名 + 絵文字` の通知を出す

### Fixed emoji set

`🏪 ☕️ 🍽️ 🚻 🏠 🏢 🏫 🤫 🚑`

## Delivery model

```text
[Sender iPhone / Watch]
        |
        v
[7Go4 server]
        |
        +--> store signal (latest 100 pending)
        |
        +--> APNs (priority 10, alert push)
                |
                +--> recipient Apple Watch
                +--> recipient iPhone
```

### Why this shape

- `WatchConnectivity` は同一ユーザーの iPhone <-> Watch 連携用で、別ユーザー間の運搬路ではない
- 閉じた状態で相手を呼び出すには、実用上 `APNs` が正道
- Watch 前面時の拡張として、後から `ライブ振動` を追加する

## Backend responsibilities

### Existing endpoints

- `POST /register`
- `GET /friends`
- `POST /signal`
- `GET /signals/pending`
- `DELETE /friends/:id`
- `DELETE /account`

### New endpoints for 7Go4

- `GET /pairing-code`
- `POST /pair`
- `POST /devices/register`

### Storage

- `users`
- `sessions`
- `friends`
- `pair_codes`
- `devices`
- `signals`

## App responsibilities

### iPhone

- Sign in with Apple
- Push token registration
- Pair code display / redeem
- Friend list + emoji send board
- Watch へのセッション同期

### Watch

- iPhone からセッション受信
- Push token registration
- Friend list + emoji send board
- 通知受信時の表示とハプティクス

## Constraints

### Supported today

- 閉じた状態での `1送信 = 1通知`
- 最新100件までの保留
- Watch / iPhone の両方への push

### Not guaranteed by the platform

- 閉じた状態での完全な連続ライブ振動
- 相手の集中モードを常に突破すること
- 1秒未満配信の絶対保証

## Next step after MVP

MVP を実機で安定させた後に、以下を検討する。

- Watch 前面時の `長押し -> 連続送信`
- WebSocket などを使った `ライブ振動`
- 送信遅延の可視化
- Time Sensitive Notifications の正式対応
