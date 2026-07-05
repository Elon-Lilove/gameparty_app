import SwiftUI
import UIKit

struct HomeCardStackView: View {
    let games: [Game]
    let current: Game
    let images: [String: UIImage]
    var isFavorite: Bool
    var spinning: Bool
    var onToggleFavorite: () -> Void
    var onOpen: () -> Void
    var onSwipeNext: () -> Void
    var onSwipePrev: () -> Void

    @State private var drag = CGSize.zero
    @State private var dragging = false
    @State private var motion: DeckMotion = .idle
    @State private var locked = false
    @State private var suppressTap = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                if let prev = neighbor(offset: -1) {
                    peekCard(game: prev, side: .left, width: width)
                        .onTapGesture { changeCard(direction: -1, axis: .horizontal) }
                }
                if let next = neighbor(offset: 1) {
                    peekCard(game: next, side: .right, width: width)
                        .onTapGesture { changeCard(direction: 1, axis: .horizontal) }
                }
                mainCard
                    .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: DesignTokens.stackMinHeight)
    }

    private var mainCard: some View {
        let palette = GameHeaderPalettes.palette(forGameID: current.id, in: games)
        return FeaturedGameCardView(
            game: current,
            palette: palette,
            image: images[current.id] ?? AssetStore.bundledImage(for: current.id),
            isFavorite: isFavorite,
            spinning: spinning,
            onToggleFavorite: onToggleFavorite,
            onStart: {
                guard !suppressTap, !locked else { return }
                onOpen()
            }
        )
        .rotationEffect(.degrees(Double(drag.width / DesignTokens.dragRotationDivisor)))
        .offset(x: drag.width, y: drag.height)
        .offset(motionOffset)
        .opacity(motionOpacity)
        .scaleEffect(motionScale)
        .animation(dragging ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: drag)
        .animation(.easeInOut(duration: DesignTokens.exitDuration), value: motion)
        .gesture(dragGesture)
        .id(current.id)
    }

    private enum Side { case left, right }
    private enum Axis { case vertical, horizontal }

    private func peekCard(game: Game, side: Side, width: CGFloat) -> some View {
        let palette = GameHeaderPalettes.palette(forGameID: game.id, in: games)
        let visibleWidth = max(52, (width - DesignTokens.cardWidth) / 2 - DesignTokens.peekCardInset)
        let image = images[game.id] ?? AssetStore.bundledImage(for: game.id)

        return ZStack(alignment: side == .left ? .leading : .trailing) {
            RoundedRectangle(cornerRadius: DesignTokens.peekCornerRadius, style: .continuous)
                .fill(palette.backgroundGradient)
            VStack(alignment: side == .left ? .leading : .trailing, spacing: 5) {
                Text(game.name)
                    .font(DesignTokens.titleFont(size: 15))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)
                    .frame(width: visibleWidth, alignment: side == .left ? .leading : .trailing)
                Text(game.firstRuleLine)
                    .font(DesignTokens.bodyFont(size: 11))
                    .foregroundStyle(DesignTokens.stone600.opacity(0.72))
                    .lineLimit(2)
                    .frame(width: visibleWidth, alignment: side == .left ? .leading : .trailing)
                artPreview(image: image, game: game, side: side)
            }
            .padding(16)
        }
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight)
        .rotationEffect(.degrees(side == .left ? -DesignTokens.peekRotation : DesignTokens.peekRotation))
        .offset(x: side == .left ? -(width / 2 - DesignTokens.peekCardInset - 40) : (width / 2 - DesignTokens.peekCardInset - 40))
        .allowsHitTesting(!locked && !spinning)
    }

    @ViewBuilder
    private func artPreview(image: UIImage?, game: Game, side: Side) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.34)
                Text(game.type.emoji)
                    .font(.system(size: 36))
            }
        }
        .frame(width: DesignTokens.artWidth, height: min(DesignTokens.artHeight, 200))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.artCornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: side == .left ? .leading : .trailing)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                guard !locked, !spinning else { return }
                dragging = true
                let x = min(max(value.translation.width, -DesignTokens.dragLimitX), DesignTokens.dragLimitX)
                let y = min(max(value.translation.height, DesignTokens.dragLimitYMin), DesignTokens.dragLimitY)
                drag = CGSize(width: x, height: y)
            }
            .onEnded { value in
                guard !locked, !spinning else { return }
                dragging = false
                let horizontal = abs(drag.width) > DesignTokens.swipeThreshold
                    && abs(drag.width) > abs(drag.height)
                let upward = drag.height < -DesignTokens.swipeThreshold
                    && abs(drag.height) >= abs(drag.width) * 0.7

                if upward {
                    changeCard(direction: 1, axis: .vertical)
                    return
                }
                if horizontal {
                    changeCard(direction: drag.width < 0 ? 1 : -1, axis: .horizontal)
                    return
                }
                if abs(value.translation.width) > 7 || abs(value.translation.height) > 7 {
                    suppressTap = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        suppressTap = false
                    }
                }
                drag = .zero
            }
    }

    private func neighbor(offset: Int) -> Game? {
        guard games.count > 1 else { return nil }
        let index = games.firstIndex(where: { $0.id == current.id }) ?? 0
        return games[(index + offset + games.count) % games.count]
    }

    private func changeCard(direction: Int, axis: Axis) {
        guard !locked, !spinning, games.count >= 2 else { return }
        locked = true
        suppressTap = true
        dragging = false

        switch axis {
        case .vertical:
            motion = .exitUp
        case .horizontal:
            motion = direction == 1 ? .exitLeft : .exitRight
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + DesignTokens.exitDuration) {
            if direction == 1 { onSwipeNext() } else { onSwipePrev() }
            drag = .zero
            motion = direction == 1 ? .enterNext : .enterPrev
            DispatchQueue.main.asyncAfter(deadline: .now() + DesignTokens.enterDuration) {
                motion = .idle
                locked = false
                suppressTap = false
            }
        }
    }

    private var motionOffset: CGSize {
        switch motion {
        case .exitUp: return CGSize(width: 0, height: -120)
        case .exitLeft: return CGSize(width: -180, height: 0)
        case .exitRight: return CGSize(width: 180, height: 0)
        case .enterNext: return CGSize(width: 40, height: 0)
        case .enterPrev: return CGSize(width: -40, height: 0)
        case .idle: return .zero
        }
    }

    private var motionOpacity: Double {
        switch motion {
        case .exitUp, .exitLeft, .exitRight: return 0
        case .enterNext, .enterPrev: return 1
        case .idle: return 1
        }
    }

    private var motionScale: CGFloat {
        switch motion {
        case .enterNext, .enterPrev: return 1
        case .exitUp, .exitLeft, .exitRight: return 0.94
        case .idle: return 1
        }
    }
}
