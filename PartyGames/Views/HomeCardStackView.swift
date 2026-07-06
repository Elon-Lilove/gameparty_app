import SwiftUI

struct HomeCardStackView: View {
    let games: [Game]
    let current: Game
    let images: [String: UIImage]
    var isFavorite: (String) -> Bool
    var spinning: Bool
    var spinPhase: SpinPhase = .idle
    var spinProgress: Double = 0
    var deckScale: CGFloat = 1
    var onToggleFavorite: (String) -> Void
    var onOpen: () -> Void
    var onSwipeNext: () -> Void
    var onSwipePrev: () -> Void

    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var cardScale: CGFloat = 1
    @State private var cardOpacity: Double = 1
    @State private var leftPeekProgress: CGFloat = 0
    @State private var rightPeekProgress: CGFloat = 0
    @State private var isDragging = false
    @State private var locked = false
    @State private var suppressTap = false

    var body: some View {
        GeometryReader { proxy in
            let layoutWidth = proxy.size.width
            let peekInset = DesignTokens.peekLayoutInset(
                layoutWidth: layoutWidth,
                deckScale: deckScale
            )

            ZStack(alignment: .top) {
                if games.count >= 3, leftPeekProgress > 0.001,
                   let backfill = neighbor(offset: -2) {
                    stackBackfillCard(
                        game: backfill,
                        side: .left,
                        emergeProgress: leftPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(0)
                }

                if games.count >= 3, rightPeekProgress > 0.001,
                   let backfill = neighbor(offset: 2) {
                    stackBackfillCard(
                        game: backfill,
                        side: .right,
                        emergeProgress: rightPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(0)
                }

                // Swipe right: old main slides into the right peek slot.
                if leftPeekProgress > 0.001 {
                    stackMainToPeekCard(
                        side: .right,
                        emergeProgress: leftPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(1)
                }

                // Swipe left: old main slides into the left peek slot.
                if rightPeekProgress > 0.001 {
                    stackMainToPeekCard(
                        side: .left,
                        emergeProgress: rightPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(1)
                }

                if let prev = neighbor(offset: -1), rightPeekProgress <= 0.001 {
                    stackGameCard(
                        game: prev,
                        side: .left,
                        promoteProgress: leftPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(leftPeekProgress > 0.02 ? 2 : 1)
                    .onTapGesture { triggerSwipe(.dismissPrevious) }
                }

                if let next = neighbor(offset: 1), leftPeekProgress <= 0.001 {
                    stackGameCard(
                        game: next,
                        side: .right,
                        promoteProgress: rightPeekProgress,
                        layoutWidth: layoutWidth,
                        peekInset: peekInset
                    )
                    .zIndex(rightPeekProgress > 0.02 ? 2 : 1)
                    .onTapGesture { triggerSwipe(.dismissNext) }
                }

                mainCard(layoutWidth: layoutWidth)
                    .zIndex(spinning ? 3 : 2)
            }
        }
        .frame(height: DesignTokens.stackMinHeight)
    }

    private func stackGameCard(
        game: Game,
        side: Side,
        promoteProgress: CGFloat,
        layoutWidth: CGFloat,
        peekInset: CGFloat
    ) -> some View {
        let peekSide: DesignTokens.PeekSide = side == .left ? .left : .right
        let metrics = DesignTokens.peekLayoutMetrics(
            side: peekSide,
            progress: promoteProgress,
            layoutWidth: layoutWidth,
            peekInset: peekInset
        )
        return stackPeekCard(
            game: game,
            side: side,
            metrics: metrics,
            promoteProgress: promoteProgress,
            motionProgress: promoteProgress
        )
    }

    private func stackBackfillCard(
        game: Game,
        side: Side,
        emergeProgress: CGFloat,
        layoutWidth: CGFloat,
        peekInset: CGFloat
    ) -> some View {
        let peekSide: DesignTokens.PeekSide = side == .left ? .left : .right
        let metrics = DesignTokens.peekBackfillMetrics(
            side: peekSide,
            emergeProgress: emergeProgress,
            layoutWidth: layoutWidth,
            peekInset: peekInset
        )
        return stackPeekCard(
            game: game,
            side: side,
            metrics: metrics,
            promoteProgress: 0,
            motionProgress: emergeProgress
        )
        .opacity(min(1, max(0.55, emergeProgress)))
    }

    /// Outgoing main card moves from center into the opposite peek slot while dragging.
    private func stackMainToPeekCard(
        side: Side,
        emergeProgress: CGFloat,
        layoutWidth: CGFloat,
        peekInset: CGFloat
    ) -> some View {
        stackBackfillCard(
            game: current,
            side: side,
            emergeProgress: emergeProgress,
            layoutWidth: layoutWidth,
            peekInset: peekInset
        )
    }

    private func stackPeekCard(
        game: Game,
        side: Side,
        metrics: DesignTokens.PeekLayoutMetrics,
        promoteProgress: CGFloat,
        motionProgress: CGFloat
    ) -> some View {
        let palette = GameHeaderPalettes.palette(forGameID: game.id, in: games)
        let image = images[game.id] ?? AssetStore.bundledImage(for: game.id)
        let depth = peekDragDepth(motionProgress: motionProgress)

        return FeaturedGameCardView(
            game: game,
            palette: palette,
            image: image,
            isFavorite: isFavorite(game.id),
            promoteProgress: promoteProgress,
            onToggleFavorite: { onToggleFavorite(game.id) },
            onStart: {
                guard !suppressTap, !locked else { return }
                onOpen()
            }
        )
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardMinHeight, alignment: .top)
        .scaleEffect(metrics.uniformScale * depth.scale, anchor: DesignTokens.peekScaleAnchor)
        .blur(radius: depth.blur)
        .rotationEffect(
            .degrees(side == .left ? -metrics.rotation : metrics.rotation),
            anchor: DesignTokens.peekScaleAnchor
        )
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardMinHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(x: metrics.offsetX, y: metrics.offsetY)
        .opacity(spinning && spinPhase != .settle ? 0.88 : 1)
        .animation(
            spinning ? DesignTokens.spinFlipAnimation(phase: spinPhase, progress: spinProgress) : nil,
            value: game.id
        )
        .allowsHitTesting(!locked && !spinning && motionProgress < 0.15)
        .animation(peekInteractionAnimation, value: motionProgress)
        .id(game.id)
    }

    private func mainCard(layoutWidth: CGFloat) -> some View {
        let palette = GameHeaderPalettes.palette(forGameID: current.id, in: games)
        return FeaturedGameCardView(
            game: current,
            palette: palette,
            image: images[current.id] ?? AssetStore.bundledImage(for: current.id),
            isFavorite: isFavorite(current.id),
            promoteProgress: 1,
            onToggleFavorite: { onToggleFavorite(current.id) },
            onStart: {
                guard !suppressTap, !locked else { return }
                onOpen()
            }
        )
        .rotation3DEffect(
            .degrees(spinning ? spinTiltDegrees : cardRotation * 0.55),
            axis: (x: 0, y: 1, z: 0),
            perspective: spinning ? 0.55 : 0.92
        )
        .rotationEffect(.degrees(spinning ? 0 : cardRotation))
        .scaleEffect(spinning ? spinCardScale : cardScale)
        .scaleEffect(spinPhase == .settle ? 1.012 : 1)
        .offset(x: spinning ? 0 : cardOffset.width, y: spinning ? 0 : cardOffset.height)
        .opacity(spinning ? 1 : cardOpacity)
        .animation(
            spinning ? DesignTokens.spinFlipAnimation(phase: spinPhase, progress: spinProgress) : nil,
            value: current.id
        )
        .animation(
            spinPhase == .settle
                ? .timingCurve(0.2, 0.8, 0.2, 1, duration: DesignTokens.spinSettleMs / 1000)
                : nil,
            value: spinPhase
        )
        .transition(spinCardTransition)
        .animation(cardInteractionAnimation, value: cardOffset)
        .animation(cardInteractionAnimation, value: cardRotation)
        .animation(cardInteractionAnimation, value: cardScale)
        .animation(cardInteractionAnimation, value: cardOpacity)
        .animation(peekInteractionAnimation, value: leftPeekProgress)
        .animation(peekInteractionAnimation, value: rightPeekProgress)
        .gesture(swipeGesture(layoutWidth: layoutWidth))
        .scaleEffect(DesignTokens.mainCardScale)
        .frame(maxWidth: .infinity, alignment: .top)
        .id(current.id)
    }

    private var cardInteractionAnimation: Animation? {
        guard !spinning, !isDragging, !locked else { return nil }
        return .spring(
            response: DesignTokens.snapSpringResponse,
            dampingFraction: DesignTokens.snapSpringDamping
        )
    }

    private var peekInteractionAnimation: Animation? {
        guard !spinning, !isDragging, !locked else { return nil }
        return .spring(response: 0.38, dampingFraction: 0.82)
    }

    private var spinCardTransition: AnyTransition {
        guard spinning else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var spinTiltDegrees: Double {
        switch spinPhase {
        case .accelerate, .chaos: -10
        case .decelerate: -5
        default: 0
        }
    }

    private var spinCardScale: CGFloat {
        switch spinPhase {
        case .accelerate, .chaos: 0.985
        case .decelerate: 0.992
        default: 1
        }
    }

    private enum Side { case left, right }

    /// Blur + slight scale-down for peeks that stay in the background during a drag.
    private func peekDragDepth(motionProgress: CGFloat) -> (blur: CGFloat, scale: CGFloat) {
        guard isDragging || locked else { return (0, 1) }
        let depth = 1 - min(1, max(0, motionProgress))
        return (
            DesignTokens.peekBlurMaxRadius * depth,
            1 - DesignTokens.peekBackgroundScaleReduction * depth
        )
    }

    private func swipeGesture(layoutWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !locked, !spinning else { return }
                isDragging = true
                applyDragVisuals(CardSwipePhysics.visuals(translation: value.translation))
            }
            .onEnded { value in
                guard !locked, !spinning else { return }
                isDragging = false
                let decision = CardSwipePhysics.decision(
                    translation: value.translation,
                    velocity: value.velocity
                )

                if decision == .snapBack {
                    if abs(value.translation.width) > 8 || abs(value.translation.height) > 8 {
                        suppressTap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            suppressTap = false
                        }
                    }
                    snapBack()
                    return
                }

                triggerSwipe(decision, layoutWidth: layoutWidth, release: value)
            }
    }

    private func applyDragVisuals(_ visuals: CardSwipePhysics.DragVisuals) {
        cardOffset = visuals.offset
        cardRotation = visuals.rotation
        cardScale = visuals.scale
        cardOpacity = 1
        leftPeekProgress = visuals.leftPeekProgress
        rightPeekProgress = visuals.rightPeekProgress
    }

    private func snapBack() {
        withAnimation(
            .spring(
                response: DesignTokens.snapSpringResponse,
                dampingFraction: DesignTokens.snapSpringDamping
            )
        ) {
            resetCardTransforms()
        }
    }

    private func triggerSwipe(
        _ decision: CardSwipePhysics.Decision,
        layoutWidth: CGFloat? = nil,
        release: DragGesture.Value? = nil
    ) {
        guard !locked, !spinning, games.count >= 2 else { return }
        HapticService.medium()
        locked = true
        suppressTap = true
        isDragging = false

        let width = layoutWidth ?? DesignTokens.baselineWidth
        let translation = release?.translation ?? cardOffset
        let velocity = release?.velocity ?? .zero
        let flyPlan = CardSwipePhysics.flyOutPlan(
            decision: decision,
            translation: translation,
            velocity: velocity,
            layoutWidth: width
        )
        let exitSlide = DesignTokens.flyOutAnimation(duration: flyPlan.duration)

        withAnimation(exitSlide) {
            cardOffset = flyPlan.target
            cardRotation = CardSwipePhysics.exitRotation(
                decision: decision,
                currentRotation: cardRotation
            )
        } completion: {
            withAnimation(DesignTokens.flyOutFadeAnimation) {
                cardOpacity = 0
            } completion: {
                switch decision {
                case .dismissNext, .dismissUp:
                    onSwipeNext()
                case .dismissPrevious:
                    onSwipePrev()
                case .snapBack:
                    break
                }
                finishSwipeTransition()
            }
        }
        withAnimation(exitSlide) {
            promotePeekToFull(for: decision)
        }
    }

    private func promotePeekToFull(for decision: CardSwipePhysics.Decision) {
        switch decision {
        case .dismissNext, .dismissUp:
            rightPeekProgress = 1
        case .dismissPrevious:
            leftPeekProgress = 1
        case .snapBack:
            break
        }
    }

    private func finishSwipeTransition() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetCardTransforms()
        }
        locked = false
        suppressTap = false
    }

    private func resetCardTransforms() {
        cardOffset = .zero
        cardRotation = 0
        cardScale = 1
        cardOpacity = 1
        leftPeekProgress = 0
        rightPeekProgress = 0
    }

    private func neighbor(offset: Int) -> Game? {
        guard games.count > 1 else { return nil }
        let index = games.firstIndex(where: { $0.id == current.id }) ?? 0
        return games[(index + offset + games.count) % games.count]
    }
}
