import SwiftUI

struct DiceToolView: View {
    private static let diceEmoji = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]

    @State private var value = 1
    @State private var rolling = false
    @State private var rollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Text("点击掷骰，随机生成 1 到 6 点，适合酒桌小游戏或随机决定。")
                .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.stone500)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Text(Self.diceEmoji[value - 1])
                    .font(.system(size: 88))
                    .frame(width: 160, height: 160)
                    .background(
                        LinearGradient(
                            colors: [
                                DesignTokens.surfaceInset,
                                DesignTokens.surfaceElevated,
                                DesignTokens.surfaceMuted,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .scaleEffect(rolling ? 1.05 : 1)
                    .animation(rolling ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : .default, value: rolling)

                Text("\(value) 点")
                    .font(DesignTokens.titleFont(size: 24))
                    .foregroundStyle(DesignTokens.stone900)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            }

            Button(action: rollDice) {
                Text(rolling ? "掷骰中…" : "掷骰子")
                    .font(DesignTokens.bodyFont(size: 14))
                    .foregroundStyle(DesignTokens.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DesignTokens.inverseSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.hapticPlain)
            .disabled(rolling)
            .opacity(rolling ? 0.6 : 1)
        }
        .onDisappear {
            rollTask?.cancel()
        }
    }

    private func rollDice() {
        guard !rolling else { return }
        rolling = true

        rollTask?.cancel()
        rollTask = Task {
            var ticks = 0
            while !Task.isCancelled, ticks < 10 {
                value = Int.random(in: 1...6)
                ticks += 1
                try? await Task.sleep(for: .milliseconds(70))
            }
            guard !Task.isCancelled else { return }
            value = Int.random(in: 1...6)
            rolling = false
            HapticService.medium()
        }
    }
}
