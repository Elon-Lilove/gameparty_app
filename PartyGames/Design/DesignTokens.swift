import SwiftUI

/// Layout and motion tokens ported from the web app CSS / HomeCardStack.tsx.
enum DesignTokens {
    // MARK: - Baseline

    static let baselineWidth: CGFloat = 390
    static let pageHorizontalPadding: CGFloat = 16

    // MARK: - Colors

    static let creamBackground = Color(red: 0.969, green: 0.957, blue: 0.937)
    static let stone900 = Color(red: 0.11, green: 0.09, blue: 0.07)
    static let stone600 = Color(red: 0.47, green: 0.44, blue: 0.42)
    static let stone500 = Color(red: 0.55, green: 0.52, blue: 0.48)
    static let stone400 = Color(red: 0.66, green: 0.63, blue: 0.60)
    static let moodActiveBorder = Color(red: 0.961, green: 0.835, blue: 0.396)
    static let moodActiveBackground = Color(red: 1.0, green: 0.984, blue: 0.922)
    static let brandYellow = Color(red: 0.961, green: 0.773, blue: 0.094)
    static let actionOrange = Color(red: 1.0, green: 0.741, blue: 0.247)
    static let actionCoral = Color(red: 1.0, green: 0.463, blue: 0.373)
    static let actionPink = Color(red: 0.929, green: 0.310, blue: 0.576)

    // MARK: - Card geometry

    static let cardWidth: CGFloat = 248
    static let cardHeight: CGFloat = 436
    static let cardMinHeight: CGFloat = 390
    static let peekCardHeight: CGFloat = 390
    static let cardCornerRadius: CGFloat = 30
    static let peekCornerRadius: CGFloat = 30
    static let artWidth: CGFloat = 216
    static let artHeight: CGFloat = 240
    static let artCornerRadius: CGFloat = 18
    static let peekCardInset: CGFloat = 16
    static let peekEdgeInset: CGFloat = 16
    static let peekVisibleMinWidth: CGFloat = 52
    static let peekCenterPull: CGFloat = 12
    static let mainCardScale: CGFloat = 1
    static let peekRotation: Double = 2
    static let stackMinHeight: CGFloat = 416
    static let cardAspectRatio: CGFloat = cardWidth / cardMinHeight
    static let deckMinScale: CGFloat = 0.82
    /// Intentional breathing room above the card stack.
    static let cardZoneTopInset: CGFloat = 16
    /// Gap between card shadow edge and the dice action row.
    static let cardAboveActionGap: CGFloat = 8
    /// Space reserved below the card layout box for its drop shadow.
    static let cardShadowOverflow: CGFloat = 32

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
    static let sideActionWidth: CGFloat = 76
    static let sideActionHeight: CGFloat = 48
    static let sideActionCornerRadius: CGFloat = 20
    static let sideActionFontSize: CGFloat = 9
    static let diceButtonDiameter: CGFloat = 64
    static let diceGlowDiameter: CGFloat = 70
    static let diceFaceSize: CGFloat = 36
    static let diceLabelSize: CGFloat = 10
    static let tabBarHeight: CGFloat = 67
    static let controlToTabGap: CGFloat = 6

    // MARK: - Drag / swipe (HomeCardStack.tsx)

    static let dragLimitX: CGFloat = 126
    static let dragLimitY: CGFloat = 72
    static let dragLimitYMin: CGFloat = -126
    static let swipeThreshold: CGFloat = 64
    static let dragRotationDivisor: CGFloat = 19

    // MARK: - Animation durations

    static let exitDuration: Double = 0.22
    static let enterDuration: Double = 0.38

    // MARK: - Spin

    static let spinDurationMs: Double = 720
    static let spinPressMs: Double = 35
    static let spinSoftStartMs: Double = 55
    static let spinDiceFaceMs: Double = 70

    // MARK: - Promo

    static let promoCountdownSeconds: Int = 5
    static let promoCollapseMs: Double = 0.32

    // MARK: - Typography

    static func titleFont(size: CGFloat = 22) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func bodyFont(size: CGFloat = 14, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Scaling

    static func scale(for width: CGFloat) -> CGFloat {
        width / baselineWidth
    }

    static func scaled(_ value: CGFloat, width: CGFloat) -> CGFloat {
        value * scale(for: width)
    }

    /// Uniform scale so the deck fills the available height while keeping 248:390 proportions.
    static func deckScale(zoneWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let stackWidth = zoneWidth + pageHorizontalPadding * 2
        let heightScale = max(0, availableHeight) / stackMinHeight
        let widthScale = stackWidth / baselineWidth
        return max(deckMinScale, min(heightScale, widthScale))
    }
}

extension View {
    func creamBackground() -> some View {
        background(DesignTokens.creamBackground.ignoresSafeArea())
    }
}
