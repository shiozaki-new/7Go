import SwiftUI
import UserNotifications
import WatchKit

// MARK: - Signal Store

@MainActor
@Observable
final class SignalStore {
    static let shared = SignalStore()

    var lastSenderName: String?
    var lastReceivedDate: Date?
    var notificationPermission: UNAuthorizationStatus = .notDetermined
    var showPulse: Bool = false
    var signalCount: Int = 0
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

    func recordSignal(from sender: String, notificationID: String? = nil) {
        if let notificationID, notificationID == lastNotificationIdentifier {
            return
        }
        lastNotificationIdentifier = notificationID
        lastSenderName = sender
        lastReceivedDate = Date()
        signalCount += 1

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
            return "まだシグナルはありません"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "\(name) — \(relative)"
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(SignalStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var animatePulse = false

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("7Go")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.tint)
                Spacer()
                if store.signalCount > 0 {
                    Text("\(store.signalCount)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint, in: Capsule())
                }
            }
            .padding(.horizontal, 4)

            Spacer()

            // Signal indicator
            ZStack {
                if animatePulse {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 70, height: 70)
                        .scaleEffect(animatePulse ? 1.6 : 1.0)
                        .opacity(animatePulse ? 0 : 0.8)

                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 70, height: 70)
                        .scaleEffect(animatePulse ? 2.0 : 1.0)
                        .opacity(animatePulse ? 0 : 0.6)
                }

                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, options: .repeating,
                                          isActive: animatePulse)
                    }
                    .scaleEffect(animatePulse ? 1.1 : 1.0)
            }
            .animation(.easeInOut(duration: 1.2), value: animatePulse)

            Spacer()

            // Last signal info
            VStack(spacing: 4) {
                Text("最後のシグナル")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(store.lastReceivedText)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(store.statusColor)
                    .frame(width: 6, height: 6)
                Text(store.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .task {
            await store.refreshNotificationStatus()
        }
        .onChange(of: store.showPulse) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.2)) {
                    animatePulse = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation {
                        animatePulse = false
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await store.refreshNotificationStatus()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SignalStore.shared)
}
