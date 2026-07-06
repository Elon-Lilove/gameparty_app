import CoreGraphics
import Foundation

/// Gesture momentum for the dice spin knob, modeled after iOS inertia scrolling
/// (see https://my.oschina.net/o2team/blog/4307027).
struct SpinMomentum: Sendable {
    let distance: CGFloat
    let durationMs: CGFloat
    let releaseSpeed: CGFloat

    /// Tap random button — full card inertia coast (~2.2s, ease-out deceleration).
    static let tapInertia = SpinMomentum(
        distance: 72,
        durationMs: 110,
        releaseSpeed: 420
    )

    /// Blog formula: `speed = 2 * |distance| / duration` (no squaring — avoids overshoot).
    var sampledSpeed: CGFloat {
        guard durationMs > 0 else { return 0 }
        return 2 * distance / durationMs
    }

    /// px/ms — combines the last sampling window and release velocity.
    var intensity: CGFloat {
        max(sampledSpeed, releaseSpeed / 1000)
    }

    var qualifiesForInertia: Bool {
        distance > DesignTokens.spinMomentumDistanceThreshold
            && durationMs < DesignTokens.spinMomentumTimeThresholdMs
    }

    /// Inertial coast distance: `speed / deceleration`.
    var coastDistance: CGFloat {
        intensity / DesignTokens.spinDeceleration
    }

    /// Stronger flicks coast longer (720ms … 2500ms).
    var spinDurationMs: Double {
        let minMs = DesignTokens.spinDurationMs
        let maxMs = DesignTokens.spinMaxDurationMs
        guard qualifiesForInertia || intensity > 0.02 else { return minMs }
        let normalized = min(1, intensity / DesignTokens.spinMaxIntensity)
        return minMs + (maxMs - minMs) * CubicBezierTiming.easeOutMomentum(normalized)
    }

    /// Extra full-deck laps before landing on the target card.
    var extraRevolutions: Int {
        guard qualifiesForInertia || intensity > 0.08 else { return 0 }
        return min(DesignTokens.spinMaxExtraRevolutions, Int(floor(intensity / 0.10)))
    }

    static func fromRelease(
        windowDistance: CGFloat,
        windowDurationMs: CGFloat,
        releaseVelocity: CGSize
    ) -> SpinMomentum {
        SpinMomentum(
            distance: windowDistance,
            durationMs: max(1, windowDurationMs),
            releaseSpeed: hypot(releaseVelocity.width, releaseVelocity.height)
        )
    }
}

enum CubicBezierTiming {
    /// `cubic-bezier(.17, .89, .45, 1)` — inertia ease-out from the OSChina article.
    private static let momentum = (x1: 0.17, y1: 0.89, x2: 0.45, y2: 1.0)

    static func easeOutMomentum(_ t: Double) -> Double {
        solve(progressX: t, control: momentum)
    }

    /// Maps linear elapsed time (0…1) to deck motion progress with deceleration.
    static func spinProgress(at t: Double) -> Double {
        solve(progressX: min(1, max(0, t)), control: momentum)
    }

    private static func solve(
        progressX targetX: Double,
        control: (x1: Double, y1: Double, x2: Double, y2: Double)
    ) -> Double {
        if targetX <= 0 { return 0 }
        if targetX >= 1 { return 1 }

        var parameter = targetX
        for _ in 0..<8 {
            let x = cubic(parameter, control.x1, control.x2) - targetX
            let derivative = cubicDerivative(parameter, control.x1, control.x2)
            if abs(derivative) < 1e-6 { break }
            parameter -= x / derivative
            parameter = min(1, max(0, parameter))
        }
        return cubic(parameter, control.y1, control.y2)
    }

    private static func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let c = 3 * a
        let d = 3 * (b - a) - c
        let e = 1 - c - d
        return ((e * t + d) * t + c) * t
    }

    private static func cubicDerivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let c = 3 * a
        let d = 3 * (b - a) - c
        let e = 1 - c - d
        return (3 * e * t + 2 * d) * t + c
    }
}
