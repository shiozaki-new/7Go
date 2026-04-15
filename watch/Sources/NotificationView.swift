import SwiftUI
import UserNotifications
import WatchKit

// MARK: - Notification Controller

final class NotificationController: WKUserNotificationHostingController<NotificationView> {
    var senderName: String = ""
    var emoji: String = "☕️"

    override var body: NotificationView {
        NotificationView(senderName: senderName, emoji: emoji)
    }

    override func didReceive(_ notification: UNNotification) {
        senderName = NotificationPayload.senderName(from: notification)
        emoji = NotificationPayload.emoji(from: notification) ?? "☕️"

        Task { @MainActor in
            SignalStore.shared.recordSignal(
                from: senderName,
                emoji: emoji,
                notificationID: notification.request.identifier
            )
        }
    }
}

// MARK: - Notification View

struct NotificationView: View {
    let senderName: String
    let emoji: String

    var body: some View {
        VStack(spacing: 12) {
            Text("7Go4")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.tint)

            Text(emoji)
                .font(.system(size: 34))

            Text(senderName)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("からシグナルが届きました")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    NotificationView(senderName: "太郎", emoji: "☕️")
}
