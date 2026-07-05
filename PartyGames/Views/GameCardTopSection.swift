import SwiftUI

/// Shared title / description / art block used by the main card and peek cards.
struct GameCardTopSection: View {
    enum Layout {
        case main
        case peek(visibleWidth: CGFloat, side: HorizontalAlignment)
    }

    let game: Game
    let palette: GameHeaderPalette
    var image: UIImage?
    var layout: Layout = .main
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
        case .main:
            mainBody
        case let .peek(visibleWidth, side):
            peekBody(visibleWidth: visibleWidth, side: side)
        }
    }

    private var mainBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            artArea
        }
    }

    private func peekBody(visibleWidth: CGFloat, side: HorizontalAlignment) -> some View {
        VStack(alignment: side, spacing: 0) {
            peekTitleHeader(visibleWidth: visibleWidth, side: side)

            Text(descriptionText)
                .font(DesignTokens.bodyFont(size: DesignTokens.cardDescSize))
                .foregroundStyle(DesignTokens.stone600.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(side == .leading ? .leading : .trailing)
                .frame(width: visibleWidth, alignment: side == .leading ? .leading : .trailing)
                .padding(.top, 6)

            peekArtArea(visibleWidth: visibleWidth, side: side)
        }
        .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : .trailing)
    }

    private func peekTitleHeader(visibleWidth: CGFloat, side: HorizontalAlignment) -> some View {
        Text(game.name)
            .font(DesignTokens.titleFont(size: DesignTokens.cardTitleSize))
            .foregroundStyle(DesignTokens.stone900)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: visibleWidth, alignment: side == .leading ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : .trailing)
            .frame(height: DesignTokens.cardHeaderHeight, alignment: .top)
    }

    private var titleText: some View {
        Text(game.name)
            .font(DesignTokens.titleFont(size: DesignTokens.cardTitleSize))
            .foregroundStyle(DesignTokens.stone900)
            .lineLimit(1)
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

            if showsFavorite, let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isFavorite ? DesignTokens.brandYellow : Color(white: 0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: DesignTokens.cardHeaderHeight)
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

    private func peekArtArea(visibleWidth: CGFloat, side: HorizontalAlignment) -> some View {
        artContent
            .frame(width: DesignTokens.artWidth, height: DesignTokens.artHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .frame(width: visibleWidth, alignment: side == .leading ? .leading : .trailing)
            .clipped()
            .padding(.top, 10)
    }

    @ViewBuilder
    private var artContent: some View {
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
    }
}
