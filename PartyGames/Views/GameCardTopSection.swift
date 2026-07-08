import SwiftUI

/// Shared title / description / art block used by the main card and peek cards.
struct GameCardTopSection: View {
    enum Layout {
        case main
        /// Full card content; outer clipping reveals the side strip when covered by the main card.
        case peek
    }

    struct ArtDepth: Equatable {
        var imageScale: CGFloat
        var shadeOpacity: Double

        init(promoteProgress: CGFloat) {
            let progress = min(1, max(0, promoteProgress))
            imageScale = 1.08 - 0.08 * progress
            shadeOpacity = Double(0.22 * (1 - progress))
        }
    }

    let game: Game
    let palette: GameHeaderPalette
    var image: UIImage?
    var layout: Layout = .main
    var artDepth = ArtDepth(promoteProgress: 1)
    var showsFavorite: Bool = false
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)?

    private var descriptionText: String {
        if let cardDescription = game.cardDescription?.trimmingCharacters(in: .whitespaces),
           !cardDescription.isEmpty {
            return cardDescription
        }
        return game.rules.joined()
    }

    var body: some View {
        switch layout {
        case .main, .peek:
            mainBody
        }
    }

    private var mainBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            artArea
        }
    }

    private var titleFontSize: CGFloat {
        DesignTokens.cardTitleSize
    }

    private var titleText: some View {
        Text(game.name)
            .font(DesignTokens.titleFont(size: titleFontSize))
            .foregroundStyle(DesignTokens.stone900)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                titleText
                Text(game.displayBadge)
                    .font(DesignTokens.bodyFont(size: 10))
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, showsFavorite ? 28 : 0)

            if showsFavorite, let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isFavorite ? DesignTokens.brandYellow : DesignTokens.stone400)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.hapticPlain)
            }
        }
        .frame(minHeight: DesignTokens.cardHeaderHeight, alignment: .top)
    }

    private var description: some View {
        Text(descriptionText)
            .font(DesignTokens.bodyFont(size: DesignTokens.cardDescSize))
            .foregroundStyle(DesignTokens.stone600.opacity(0.88))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .center)
            .padding(.top, 6)
    }

    private var artArea: some View {
        artContent
            .frame(width: DesignTokens.artWidth, height: DesignTokens.artHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(.top, 10)
    }

    @ViewBuilder
    private var artContent: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(artDepth.imageScale)
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
            Color.white
                .opacity(artDepth.shadeOpacity)
                .allowsHitTesting(false)
        }
    }
}
