import SwiftUI

struct FeaturedGameCardView: View {
    let game: Game
    let palette: GameHeaderPalette
    var image: UIImage?
    var isFavorite: Bool
    var spinning: Bool = false
    var onToggleFavorite: () -> Void
    var onStart: () -> Void

    private var descriptionText: String {
        if let cardDescription = game.cardDescription?.trimmingCharacters(in: .whitespaces),
           !cardDescription.isEmpty {
            return cardDescription
        }
        return game.rules.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            artArea
            statsRow
            startButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
        .shadow(color: DesignTokens.actionPink.opacity(0.08), radius: 22, y: 10)
        .opacity(spinning ? 0.92 : 1)
        .scaleEffect(spinning ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.2), value: spinning)
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text(game.name)
                    .font(DesignTokens.titleFont(size: 22))
                    .foregroundStyle(DesignTokens.stone900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(game.displayBadge)
                    .font(DesignTokens.bodyFont(size: 10))
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFavorite ? DesignTokens.brandYellow : Color(white: 0.82))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    private var description: some View {
        Text(descriptionText)
            .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.stone600.opacity(0.88))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .center)
            .padding(.top, 6)
    }

    private var artArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: DesignTokens.artWidth, height: DesignTokens.artHeight)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [palette.backgroundTop, palette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(game.type.emoji)
                    .font(.system(size: 52))
            }
        }
        .frame(width: DesignTokens.artWidth, height: DesignTokens.artHeight)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .padding(.top, 10)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statItem(icon: "person.2.fill", text: game.playerLabel)
            statItem(icon: "clock.fill", text: game.displayDuration)
            statItem(icon: "bolt.fill", text: game.type.labelZh)
        }
        .frame(height: 18)
        .padding(.top, 10)
    }

    private func statItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(DesignTokens.bodyFont(size: 12))
                .lineLimit(1)
        }
        .foregroundStyle(DesignTokens.stone600)
        .frame(maxWidth: .infinity)
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(game.startButtonLabel ?? "开始游戏")
                    .font(DesignTokens.bodyFont(size: 15))
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
