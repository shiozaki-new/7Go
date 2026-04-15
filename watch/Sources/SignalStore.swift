import SwiftUI
import UserNotifications
import WatchKit

@MainActor
@Observable
final class SignalStore {
    static let shared = SignalStore()

    var lastSenderName: String?
    var lastEmoji: String?
    var lastReceivedDate: Date?
    var notificationPermission: UNAuthorizationStatus = .notDetermined
    var showPulse: Bool = false
    private var lastNotificationIdentifier: String?

    var isConnected: Bool {
        notificationPermission == .authorized || notificationPermission == .provisional
    }

    var statusText: String {
        switch notificationPermission {
        case .authorized, .provisional:
            return "通知待機中"
        case .denied:
            return "通知未許可"
        case .notDetermined:
            return "通知未設定"
        @unknown default:
            return "状態不明"
        }
    }

    var statusColor: Color {
        switch notificationPermission {
        case .authorized, .provisional:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    func recordSignal(from sender: String, emoji: String? = nil, notificationID: String? = nil) {
        if let notificationID, notificationID == lastNotificationIdentifier {
            return
        }
        lastNotificationIdentifier = notificationID
        lastSenderName = sender
        lastEmoji = emoji
        lastReceivedDate = Date()

        showPulse = true
        WKInterfaceDevice.current().play(.notification)

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showPulse = false
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus
    }

    var lastReceivedText: String {
        guard let name = lastSenderName, let date = lastReceivedDate else {
            return "まだ通知はありません"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        let emojiSuffix = lastEmoji.map { " \($0)" } ?? ""
        return "\(name)\(emojiSuffix) - \(relative)"
    }
}
