import Foundation
import UserNotifications

enum NotificationPayload {
    static func senderName(from notification: UNNotification) -> String {
        senderName(from: notification.request.content)
    }

    static func senderName(from content: UNNotificationContent) -> String {
        if let senderName = nonEmptyString(content.userInfo["senderName"] as? String) {
            return senderName
        }

        // `ntfy` mirrored notifications do not carry 7Go's custom `userInfo`,
        // so fall back to the title/body until APNs delivers structured payloads.
        if let senderName = senderNameFromTitle(content.title) {
            return senderName
        }
        if let senderName = senderNameFromBody(content.body) {
            return senderName
        }

        return "不明"
    }

    private static func senderNameFromTitle(_ title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        for separator in ["—", "-", ":"] {
            let parts = trimmedTitle.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let prefix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard prefix == "7go" else { continue }

            let suffix = parts[1...].joined(separator: separator)
            if let senderName = nonEmptyString(suffix) {
                return senderName
            }
        }

        return nil
    }

    private static func senderNameFromBody(_ body: String) -> String? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorRange = trimmedBody.range(of: " が") else {
            return nil
        }
        let candidate = String(trimmedBody[..<separatorRange.lowerBound])
        return nonEmptyString(candidate)
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
