# Signal Architecture

## Short answer

Yes, you can build an app where a sender picks a name and presses one button, and the other person's Apple Watch alerts.

The supported way to do that is not "watch to watch" direct signaling.
The supported path is:

- sender app -> your server -> push delivery service -> recipient device -> Apple Watch notification haptic

## Prototype path in this repo

The fastest working version is:

- sender iPhone app
- your small HTTPS server
- `ntfy` topic per recipient
- recipient iPhone and Apple Watch running the `ntfy` app

Flow:

- sender iPhone app -> `POST /signal`
- server looks up the target person
- server publishes to `https://ntfy.sh/<secret-topic>`
- `ntfy` delivers a notification to the recipient device
- Apple Watch plays the notification haptic

## Production path

The App Store friendly version is:

- sender iPhone app -> your backend -> APNs -> recipient iPhone/watch app notification -> system haptic on Apple Watch

If the receiver watch app is already active on screen, the watch app can also trigger a local haptic with:

- `WKInterfaceDevice.current().play(.notification)`

Official API link:

- `https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)`

## How the signal is really sent

The server is the hub.

The sender app should never know how to reach the recipient watch directly.
Instead, the sender app sends:

- who to notify
- who sent it
- optional message metadata

The server then maps that person to a delivery target:

- prototype: a private `ntfy` topic
- production: an APNs device token for that user's app

## Why not WatchConnectivity for cross-user signaling

`WatchConnectivity` is only for a person's iPhone app talking to that same person's paired watch app.
It is not the internet transport between two different users.

Use it only after the receiving phone already has the signal and you want to mirror state into that user's watch app.

Apple references:

- `https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity`
- `https://developer.apple.com/videos/play/wwdc2021/10003/`

Apple's WWDC21 Watch Connectivity session describes `applicationContext`, `transferUserInfo`, and `sendMessage` as paired-device transfer tools, and notes that `sendMessage` requires the counterpart app to be reachable.

## Apple notification constraints

Apple's notification docs state that local and remote notifications are the supported way to alert people even when the app is not in the foreground, and that remote notifications require your own provider server that sends data to APNs.

Official sources:

- `https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications`
- `https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/`
- `https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/HandlingRemoteNotifications.html`
- `https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app`

Relevant points from those sources:

- remote notifications are for server-to-device delivery
- your app must obtain permission for alerts and sounds
- your app must register with APNs and forward the device token to your server
- archived Apple docs note that watchOS notifications are forwarded from the paired iPhone to Apple Watch when the iPhone is locked or asleep and the watch is on wrist and unlocked

## Practical inference

This is an inference from the official APIs above:

- a general-purpose "silent remote vibrate another user's Apple Watch at any time" flow is not the standard app model
- a visible notification is the normal remote delivery path
- direct haptic playback is local to the watch app code running on the recipient device
