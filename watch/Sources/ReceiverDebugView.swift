import SwiftUI
import WatchKit

struct ReceiverDebugView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Receiver Debug")
                .font(.headline)

            Button("Play Local Haptic") {
                WKInterfaceDevice.current().play(.notification)
            }
            .buttonStyle(.borderedProminent)

            Text("Use this only for local testing while the watch app is active.")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ReceiverDebugView()
}
