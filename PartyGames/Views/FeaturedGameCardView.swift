import SwiftUI

struct FeaturedGameCardView: View {
    let game: Game
    let palette: GameHeaderPalette
    var image: UIImage?
    var isFavorite: Bool
    var spinning: Bool = false
    var onToggleFavorite: () -> Void
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameCardTopSection(
                game: game,
                palette: palette,
                image: image,
                showsFavorite: true,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite
            )
            statsRow
            startButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: DesignTokens.cardWidth)
        .aspectRatio(DesignTokens.cardAspectRatio, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
        .shadow(color: DesignTokens.actionPink.opacity(0.08), radius: 22, y: 10)
        .opacity(spinning ? 0.92 : 1)
        .scaleEffect(spinning ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.2), value: spinning)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statItem(icon: "person.2.fill", text: game.playerLabel)
            statItem(icon: "clock.fill", text: game.displayDuration)
            statItem(icon: "bolt.fill", text: game.type.labelZh)
        }
        .frame(height: 17)
        .padding(.top, 12)
    }

    private func statItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(DesignTokens.bodyFont(size: DesignTokens.cardStatsSize))
                .lineLimit(1)
        }
        .foregroundStyle(DesignTokens.stone600)
        .frame(maxWidth: .infinity)
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(game.startButtonLabel ?? "开始游戏")
                    .font(DesignTokens.bodyFont(size: DesignTokens.cardStartSize))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                LinearGradient(
                    colors: [DesignTokens.actionOrange, DesignTokens.actionCoral, DesignTokens.actionPink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: DesignTokens.actionPink.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }
}
