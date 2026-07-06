import SwiftUI
import UIKit

/// Layout and motion tokens ported from the web app CSS / HomeCardStack.tsx.
enum DesignTokens {
    // MARK: - Baseline

    static let baselineWidth: CGFloat = 390
    static let pageHorizontalPadding: CGFloat = 16

    // MARK: - Colors (light / dark adaptive)

    /// Main screen background: cream in light mode, black in dark mode.
    static let pageBackground = Color.adaptive(
        light: Color(red: 0.969, green: 0.957, blue: 0.937),
        dark: .black
    )

    /// Backward-compatible alias used across views.
    static var creamBackground: Color { pageBackground }

    static let stone900 = Color.adaptive(
        light: Color(red: 0.11, green: 0.09, blue: 0.07),
        dark: .white
    )

    static let stone600 = Color.adaptive(
        light: Color(red: 0.47, green: 0.44, blue: 0.42),
        dark: Color(white: 0.78)
    )

    static let stone500 = Color.adaptive(
        light: Color(red: 0.55, green: 0.52, blue: 0.48),
        dark: Color(white: 0.66)
    )

    static let stone400 = Color.adaptive(
        light: Color(red: 0.66, green: 0.63, blue: 0.60),
        dark: Color(white: 0.52)
    )

    static let surfaceElevated = Color.adaptive(
        light: .white,
        dark: Color(red: 0.11, green: 0.11, blue: 0.12)
    )

    static let surfaceElevatedSoft = Color.adaptive(
        light: Color.white.opacity(0.82),
        dark: Color(white: 0.14)
    )

    static let surfaceMuted = Color.adaptive(
        light: Color(white: 0.96),
        dark: Color(white: 0.10)
    )

    static let surfaceInset = Color.adaptive(
        light: Color(white: 0.94),
        dark: Color(white: 0.18)
    )

    static let cardBackground = Color.adaptive(
        light: .white,
        dark: Color(red: 0.14, green: 0.14, blue: 0.15)
    )

    static let borderSubtle = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor(red: 0.66, green: 0.63, blue: 0.60, alpha: 0.18)
    })

    /// Filled pill / button surface that inverts with appearance.
    static let inverseSurface = Color.adaptive(
        light: Color(red: 0.11, green: 0.09, blue: 0.07),
        dark: .white
    )

    static let inverseText = Color.adaptive(
        light: .white,
        dark: .black
    )

    static let tabAccent = Color.adaptive(
        light: Color(red: 0.961, green: 0.773, blue: 0.094),
        dark: .white
    )

    static let moodActiveBorder = Color(red: 0.961, green: 0.835, blue: 0.396)
    static let moodActiveBackground = Color.adaptive(
        light: Color(red: 1.0, green: 0.984, blue: 0.922),
        dark: Color(white: 0.18)
    )
    static let brandYellow = Color(red: 0.961, green: 0.773, blue: 0.094)
    static let actionOrange = Color(red: 1.0, green: 0.741, blue: 0.247)
    static let actionCoral = Color(red: 1.0, green: 0.463, blue: 0.373)
    static let actionPink = Color(red: 0.929, green: 0.310, blue: 0.576)

    static var uiPrimaryText: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .white
                : UIColor(red: 0.11, green: 0.09, blue: 0.07, alpha: 1)
        }
    }

    // MARK: - Card geometry

    static let cardWidth: CGFloat = 248
    static let cardHeight: CGFloat = 436
    static let cardMinHeight: CGFloat = 390
    static let cardCornerRadius: CGFloat = 30
    static let peekCornerRadius: CGFloat = 30
    static let artWidth: CGFloat = 216
    static let artHeight: CGFloat = 240
    static let artCornerRadius: CGFloat = 18
    static let peekCardInset: CGFloat = 16
    static let peekEdgeInset: CGFloat = 16
    static let peekVisibleMinWidth: CGFloat = 52
    /// Extra inset so rotated peek corners stay inside the screen.
    static let peekRotationSafeInset: CGFloat = 22
    static let mainCardScale: CGFloat = 1
    /// Static peek top sits below the main top by this fraction of card height (10–20%).
    static let peekTopDropFraction: CGFloat = 0.15
    /// Uniform peek scale; keeps aspect ratio identical to the main card.
    static var peekCardScale: CGFloat { 1 - peekTopDropFraction }
    /// Peek cards use uniform scale only — never taller than the main card.
    static let peekTopStretch: CGFloat = 1
    /// Minimum fraction of peek card width that stays geographically on-screen.
    static let peekOnScreenFraction: CGFloat = 0.55
    /// Fan rotation at rest; cards pivot on the shared bottom edge.
    static let peekFanRotation: Double = 4
    /// Static peek bottom sits above the main bottom by this fraction of card height.
    static let peekBottomLiftFraction: CGFloat = 0.07
    /// Extra space below the main card bottom so peek rotation/shadow are not clipped.
    static let peekBottomBleed: CGFloat = 14
    static var stackMinHeight: CGFloat {
        cardMinHeight + peekBottomBleed
    }
    static let cardAspectRatio: CGFloat = cardWidth / cardMinHeight
    static let deckMinScale: CGFloat = 0.82
    /// Max upscale past baseline width when filling vertical space (peek insets absorb overflow).
    static let deckMaxUpscale: CGFloat = 1.12
    /// Gap between the mood row and the card stack.
    static let cardZoneTopInset: CGFloat = 14
    /// Gap between card shadow edge and the dice action row.
    static let cardAboveActionGap: CGFloat = 22
    /// Space reserved below the card layout box for its drop shadow.
    static let cardShadowOverflow: CGFloat = 16

    static var cardBottomReserve: CGFloat {
        cardAboveActionGap + cardShadowOverflow
    }

    // MARK: - Card typography (measured from web at 390pt baseline)

    static let cardTitleSize: CGFloat = 19
    static let cardHeaderHeight: CGFloat = 44
    static let cardDescSize: CGFloat = 11
    static let cardStatsSize: CGFloat = 11
    static let cardStartSize: CGFloat = 12
    static let peekTitleSize: CGFloat = 14
    static let peekDescSize: CGFloat = 10

    // MARK: - Home controls (measured from the 390 × 844 web reference)

    static let homeActionBarHeight: CGFloat = 90
    static let sideActionWidth: CGFloat = 104
    static let sideActionHeight: CGFloat = 44
    static let sideActionCornerRadius: CGFloat = 22
    static let sideActionFontSize: CGFloat = 11
    static let diceButtonDiameter: CGFloat = 64
    static let diceGlowDiameter: CGFloat = 70
    static let diceFaceSize: CGFloat = 36
    static let diceLabelSize: CGFloat = 10
    static let tabBarHeight: CGFloat = 67
    static let controlToTabGap: CGFloat = 6

    // MARK: - Drag / swipe (Tinder-style card physics)

    static let swipeThreshold: CGFloat = 80
    static let swipeVelocityThreshold: CGFloat = 420
    static let swipeUpPositionThreshold: CGFloat = 88
    static let swipeVelocityProjection: CGFloat = 0.28
    static let flyOutVelocityProjectionBoost: CGFloat = 0.18
    static let flyOutExtraDistanceBase: CGFloat = 100
    static let flyOutExtraDistanceLayoutFactor: CGFloat = 0.18
    static let flyOutSpeedNormalization: CGFloat = 900
    /// Tinder-style coast-off duration; fast flicks use the longer end.
    static let flyOutDurationMin: Double = 0.50
    static let flyOutDurationMax: Double = 0.78
    static let flyOutOpacityFadeDuration: Double = 0.12
    /// Max rotation while dragging; linear in horizontal distance.
    static let maxDragRotation: Double = 20
    static let maxExitRotation: Double = 20
    static let dragRotationDivisor: CGFloat = 16
    static let dragScaleMaxReduction: CGFloat = 0.055
    static let dragScaleFactor: CGFloat = 0.00009
    static let peekPromoteDistance: CGFloat = 110
    /// Background peek blur / scale depth while the main card is moving.
    static let peekBlurMaxRadius: CGFloat = 3.5
    static let peekBackgroundScaleReduction: CGFloat = 0.045
    /// Progress 0…this value slides the peek to the main slot; remaining progress scales up in place.
    static let peekPositionPhaseEnd: CGFloat = 0.55
    static let snapSpringResponse: CGFloat = 0.42
    static let snapSpringDamping: CGFloat = 0.62
    static let flyOutDuration: Double = 0.36
    static let peekPromoteSpringResponse: CGFloat = 0.52
    static let peekPromoteSpringDamping: CGFloat = 0.86
    /// Legacy timing hint; fly-out uses `flyOutAnimation` + completion handler.
    static let swipeFlyDuration: Double = 0.36

    /// Gentle deceleration — card coasts off screen like Tinder.
    static func flyOutAnimation(duration: Double) -> Animation {
        let clamped = min(flyOutDurationMax, max(flyOutDurationMin, duration))
        return .timingCurve(0.28, 0.82, 0.36, 1, duration: clamped)
    }

    static var flyOutFadeAnimation: Animation {
        .easeOut(duration: flyOutOpacityFadeDuration)
    }

    /// Legacy limits kept for reference; main card drag is 1:1 with finger.
    static let dragLimitX: CGFloat = 126
    static let dragLimitY: CGFloat = 72
    static let dragLimitYMin: CGFloat = -126

    // MARK: - Animation durations

    static let exitDuration: Double = 0.22
    static let enterDuration: Double = 0.38

    // MARK: - Spin

    static let spinDurationMs: Double = 720
    static let spinMaxDurationMs: Double = 2500
    static let spinSettleMs: Double = 780
    static let spinPressMs: Double = 35
    static let spinSoftStartMs: Double = 55
    static let spinDiceFaceMs: Double = 70
    /// Default inertia profile when tapping the random button.
    static let spinTapDurationMs: Double = 2200
    static let spinMomentumTimeThresholdMs: CGFloat = 300
    static let spinMomentumDistanceThreshold: CGFloat = 15
    static let spinDeceleration: CGFloat = 0.003
    static let spinMaxIntensity: CGFloat = 0.55
    static let spinMaxExtraRevolutions: Int = 3

    /// Card flip transition duration per spin phase (mirrors web deck CSS).
    static func spinFlipDuration(phase: SpinPhase, progress: Double) -> Double {
        let p = min(1, max(0, progress))
        switch phase {
        case .accelerate:
            return 0.12 + p * 0.06
        case .chaos:
            return 0.13 + p * 0.09
        case .decelerate:
            return 0.40 + p * 0.50
        case .settle:
            return spinSettleMs / 1000
        default:
            return 0.22
        }
    }

    static func spinFlipAnimation(phase: SpinPhase, progress: Double) -> Animation {
        let duration = spinFlipDuration(phase: phase, progress: progress)
        switch phase {
        case .accelerate:
            return .timingCurve(0.22, 0.8, 0.3, 1, duration: duration)
        case .chaos:
            return .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
        case .decelerate, .settle:
            return .timingCurve(0.1, 0.9, 0.2, 1, duration: duration)
        default:
            return .easeInOut(duration: duration)
        }
    }

    // MARK: - Typography

    static func titleFont(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func bodyFont(size: CGFloat = 14, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func uiTitleFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    // MARK: - Scaling

    static func scale(for width: CGFloat) -> CGFloat {
        width / baselineWidth
    }

    static func scaled(_ value: CGFloat, width: CGFloat) -> CGFloat {
        value * scale(for: width)
    }

    /// Scale the deck to fill the card zone height, capped by width × `deckMaxUpscale`.
    static func deckScale(zoneWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let heightScale = max(0, availableHeight) / stackMinHeight
        let widthCap = (zoneWidth / baselineWidth) * deckMaxUpscale
        return max(deckMinScale, min(heightScale, widthCap))
    }

    /// Screen-edge inset for peek cards (web: 16pt; extra room for ±2° rotation).
    static var peekLayoutInset: CGFloat {
        max(peekEdgeInset, peekRotationSafeInset)
    }

    static var peekCardWidth: CGFloat { cardWidth * peekCardScale }

    /// Effective Y scale: top extends upward by 8%; bottom stays fixed.
    static var peekCardVerticalScale: CGFloat { peekTopStretch }

    static var peekCardHeight: CGFloat { cardMinHeight * peekCardVerticalScale }

    /// Visual height that extends above the main card top when bottom-aligned.
    static var peekTopOverflow: CGFloat {
        cardMinHeight * (peekCardVerticalScale - 1)
    }

    static var peekScaledCornerRadius: CGFloat { peekCornerRadius * peekCardScale }

    static func peekStretchAnchor(side: PeekSide) -> UnitPoint {
        switch side {
        case .left:
            return .bottomLeading
        case .right:
            return .bottomTrailing
        }
    }

    /// Bottom edge aligns with the main card; no vertical shift.
    static var peekVerticalOffset: CGFloat { 0 }

    struct PeekLayoutMetrics: Equatable {
        let uniformScale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        let rotation: Double
    }

    /// Scale / rotation anchor — bottom edge aligns with the main card for a fan stack.
    static let peekScaleAnchor = UnitPoint.bottom

    /// Slide to the main slot first, then scale up in place from the top edge.
    static func peekLayoutMetrics(
        side: PeekSide,
        progress: CGFloat,
        layoutWidth: CGFloat,
        peekInset: CGFloat
    ) -> PeekLayoutMetrics {
        let p = min(1, max(0, progress))
        let positionEnd = peekPositionPhaseEnd
        let positionProgress = min(1, p / positionEnd)
        let scaleProgress = p <= positionEnd ? 0 : (p - positionEnd) / (1 - positionEnd)

        let uniformScale = peekCardScale + (1 - peekCardScale) * scaleProgress
        let restOffsetX = peekRestOffsetX(
            side: side,
            layoutWidth: layoutWidth,
            peekInset: peekInset,
            scale: peekCardScale
        )

        let lift = cardMinHeight * peekBottomLiftFraction * (1 - p)

        return PeekLayoutMetrics(
            uniformScale: uniformScale,
            offsetX: restOffsetX * (1 - positionProgress),
            offsetY: -lift,
            rotation: peekFanRotation * (1 - positionProgress)
        )
    }

    /// Inverse of promote — new peek emerges from the main slot toward the side rest pose.
    static func peekBackfillMetrics(
        side: PeekSide,
        emergeProgress: CGFloat,
        layoutWidth: CGFloat,
        peekInset: CGFloat
    ) -> PeekLayoutMetrics {
        let e = min(1, max(0, emergeProgress))
        let rest = peekLayoutMetrics(
            side: side,
            progress: 0,
            layoutWidth: layoutWidth,
            peekInset: peekInset
        )
        let originScale = peekCardScale * 0.94

        return PeekLayoutMetrics(
            uniformScale: originScale + (rest.uniformScale - originScale) * e,
            offsetX: rest.offsetX * e,
            offsetY: rest.offsetY * e,
            rotation: rest.rotation * e
        )
    }

    /// Horizontal offset from the centered main slot to the side peek rest position.
    static func peekRestOffsetX(
        side: PeekSide,
        layoutWidth: CGFloat,
        peekInset: CGFloat,
        scale: CGFloat = peekCardScale
    ) -> CGFloat {
        let mainCenterX = layoutWidth / 2
        let visualHalfWidth = cardWidth * scale / 2
        let restCenterX: CGFloat
        switch side {
        case .left:
            restCenterX = peekInset + visualHalfWidth
        case .right:
            restCenterX = layoutWidth - peekInset - visualHalfWidth
        }
        return restCenterX - mainCenterX
    }

    /// Leading/trailing inset in layout space so peek corners stay on-screen after `deckScale`.
    static func peekLayoutInset(layoutWidth: CGFloat, deckScale: CGFloat) -> CGFloat {
        guard deckScale > 0 else { return peekLayoutInset }
        let center = layoutWidth / 2
        let target = peekRotationSafeInset
        let compensated = center + (target - center) / deckScale
        return max(peekEdgeInset, compensated)
    }

    static func peekVisibleContentWidth(
        side: PeekSide,
        layoutWidth: CGFloat,
        mainWidth: CGFloat,
        deckScale: CGFloat = 1
    ) -> CGFloat {
        let mainLeading = (layoutWidth - mainWidth) / 2
        let mainTrailing = mainLeading + mainWidth
        let inset = peekLayoutInset(layoutWidth: layoutWidth, deckScale: deckScale)
        let peekWidth = peekCardWidth

        switch side {
        case .left:
            let exposed = mainLeading - inset
            return max(peekVisibleMinWidth, min(exposed, peekWidth * peekOnScreenFraction))
        case .right:
            let exposed = layoutWidth - inset - mainTrailing
            return max(peekVisibleMinWidth, min(exposed, peekWidth * peekOnScreenFraction))
        }
    }

    enum PeekSide {
        case left
        case right
    }
}

extension View {
    func creamBackground() -> some View {
        background(DesignTokens.pageBackground.ignoresSafeArea())
    }
}

extension Color {
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
