import SwiftUI
import UserNotifications
import WatchKit

// MARK: - Notification Controller

final class NotificationController: WKUserNotificationHostingController<NotificationView> {
    var senderName: String = ""
    var pattern: String = ""

    override var body: NotificationView {
        NotificationView(senderName: senderName, pattern: pattern)
    }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        senderName = NotificationPayload.senderName(from: notification)
        pattern = content.userInfo["pattern"] as? String ?? ""

        Task { @MainActor in
            SignalStore.shared.recordSignal(
                from: senderName,
                notificationID: notification.request.identifier
            )
        }
    }
}

// MARK: - Notification View

struct NotificationView: View {
    let senderName: String
    var pattern: String = ""

    private var patternIcon: String {
        switch pattern {
        case "おーい": "hand.wave.fill"
        case "急ぎ！": "exclamationmark.circle.fill"
        default: "hand.tap.fill"
        }
    }

    private var patternColor: Color {
        switch pattern {
        case "おーい": .purple
        case "急ぎ！": .orange
        default: .blue
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("7Go")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(patternColor)

            Image(systemName: patternIcon)
                .font(.title2)
                .foregroundStyle(patternColor)
                .symbolEffect(.bounce, options: .nonRepeating)

            Text(senderName)
                .font(.headline)
                .multilineTextAlignment(.center)

            if !pattern.isEmpty {
                Text(pattern)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("からシグナルが届きました")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    NotificationView(senderName: "太郎", pattern: "おーい")
}
