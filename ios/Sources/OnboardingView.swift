import SwiftUI

struct OnboardingView: View {
    @Environment(UserSession.self) private var session
    @State private var currentPage = 0
    @State private var showLogin = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "hand.tap.fill",
            title: "友達にシグナルを送ろう",
            subtitle: "ワンタップで友達のApple Watchを\nバイブレーションさせよう",
            color: .blue
        ),
        OnboardingPage(
            icon: "applewatch.radiowaves.left.and.right",
            title: "手首で感じる",
            subtitle: "Apple Watchでリアルタイムに\nシグナルを受け取れる",
            color: .purple
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "つながる",
            subtitle: "友達を追加して\n新しいコミュニケーションを始めよう",
            color: .orange
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(duration: 0.3), value: currentPage)
                }
            }
            .padding(.bottom, 32)

            // Action button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    withAnimation(.spring(duration: 0.4)) {
                        session.completeOnboarding()
                    }
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "次へ" : "はじめる")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 32)

            if currentPage < pages.count - 1 {
                Button {
                    withAnimation(.spring(duration: 0.4)) {
                        session.completeOnboarding()
                    }
                } label: {
                    Text("スキップ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }

            Spacer()
                .frame(height: 32)
        }
    }

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.color.opacity(0.12))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(page.color.opacity(0.06))
                    .frame(width: 200, height: 200)

                Image(systemName: page.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(page.color)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}
