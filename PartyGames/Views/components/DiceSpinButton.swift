import SwiftUI

struct DiceSpinButton: View {
    var spinning: Bool
    var disabled: Bool
    var diceFace: Int
    var onPressStart: () -> Void
    var onRelease: (SpinMomentum) -> Void

    @State private var momentumAnchor: CGPoint?
    @State private var momentumWindowStart: Date?
    @State private var didBeginPress = false

    var body: some View {
        VStack(spacing: 6) {
            diceControl
            Text("随机一局")
                .font(DesignTokens.bodyFont(size: 11))
                .foregroundStyle(DesignTokens.stone500)
        }
        .frame(height: 88, alignment: .top)
    }

    private var diceControl: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.actionOrange, DesignTokens.actionCoral, DesignTokens.actionPink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: DesignTokens.diceGlowDiameter, height: DesignTokens.diceGlowDiameter)
                .shadow(color: DesignTokens.actionCoral.opacity(0.25), radius: 10, y: 5)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 1, green: 0.95, blue: 0.91)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: DesignTokens.diceButtonDiameter, height: DesignTokens.diceButtonDiameter)
            DiceFaceView(value: spinning ? diceFace + 1 : 5)
                .frame(width: DesignTokens.diceFaceSize, height: DesignTokens.diceFaceSize)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: Color.orange.opacity(0.20), radius: 5, y: 3)
                .rotationEffect(.degrees(-8))
        }
        .scaleEffect(spinning ? 1.06 : 1)
        .rotationEffect(.degrees(spinning ? 8 : 0))
        .animation(spinning ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: spinning)
        .frame(width: DesignTokens.diceGlowDiameter, height: DesignTokens.diceGlowDiameter)
        .contentShape(Circle())
        .opacity(disabled ? 0.55 : 1)
        .allowsHitTesting(!disabled)
        .gesture(spinGesture)
    }

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let now = Date()
                if momentumAnchor == nil {
                    momentumAnchor = value.startLocation
                    momentumWindowStart = now
                    if !didBeginPress {
                        didBeginPress = true
                        onPressStart()
                    }
                }

                if let windowStart = momentumWindowStart,
                   now.timeIntervalSince(windowStart) * 1000 > DesignTokens.spinMomentumTimeThresholdMs {
                    momentumWindowStart = now
                    momentumAnchor = value.location
                }
            }
            .onEnded { value in
                defer {
                    momentumAnchor = nil
                    momentumWindowStart = nil
                    didBeginPress = false
                }
                guard !disabled else { return }

                let anchor = momentumAnchor ?? value.startLocation
                let windowDistance = hypot(
                    value.location.x - anchor.x,
                    value.location.y - anchor.y
                )
                let windowDurationMs = CGFloat(
                    (momentumWindowStart.map { Date().timeIntervalSince($0) } ?? 0) * 1000
                )
                let momentum = SpinMomentum.fromRelease(
                    windowDistance: windowDistance,
                    windowDurationMs: max(1, windowDurationMs),
                    releaseVelocity: value.velocity
                )
                onRelease(momentum)
            }
    }
}

struct DiceFaceView: View {
    let value: Int

    private var pips: [Int] {
        switch value {
        case 1: [5]
        case 2: [1, 9]
        case 3: [1, 5, 9]
        case 4: [1, 3, 7, 9]
        case 5: [1, 3, 5, 7, 9]
        default: [1, 3, 4, 6, 7, 9]
        }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(1...9, id: \.self) { index in
                Circle()
                    .fill(pips.contains(index) ? Color.orange : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(6)
    }
}
