import CoreGraphics
import Foundation

/// Tinder-style swipe physics for the main recommendation card.
enum CardSwipePhysics {
    enum Decision: Sendable {
        case snapBack
        case dismissNext
        case dismissPrevious
        case dismissUp
    }

    struct DragVisuals: Sendable {
        let offset: CGSize
        let rotation: Double
        let scale: CGFloat
        let leftPeekProgress: CGFloat
        let rightPeekProgress: CGFloat
    }

    struct FlyOutPlan: Sendable {
        let target: CGSize
        let duration: Double
    }

    static func visuals(translation: CGSize) -> DragVisuals {
        let x = translation.width
        let magnitude = hypot(x, translation.height)
        let promote = min(1, abs(x) / DesignTokens.peekPromoteDistance)
        let rawRotation = Double(x / DesignTokens.dragRotationDivisor)
        let clampedRotation = min(
            DesignTokens.maxDragRotation,
            max(-DesignTokens.maxDragRotation, rawRotation)
        )
        return DragVisuals(
            offset: translation,
            rotation: clampedRotation,
            scale: 1 - min(DesignTokens.dragScaleMaxReduction, magnitude * DesignTokens.dragScaleFactor),
            leftPeekProgress: x > 0 ? promote : 0,
            rightPeekProgress: x < 0 ? promote : 0
        )
    }

    static func decision(translation: CGSize, velocity: CGSize) -> Decision {
        let x = translation.width
        let y = translation.height
        let vx = velocity.width
        let vy = velocity.height

        if y < -DesignTokens.swipeUpPositionThreshold,
           abs(y) > abs(x) * 0.65,
           vy < -DesignTokens.swipeVelocityThreshold || y < -DesignTokens.swipeUpPositionThreshold * 1.35 {
            return .dismissUp
        }

        let horizontalDominant = abs(x) >= abs(y) * 0.85
        guard horizontalDominant else { return .snapBack }

        if x < -DesignTokens.swipeThreshold || vx < -DesignTokens.swipeVelocityThreshold {
            return .dismissNext
        }
        if x > DesignTokens.swipeThreshold || vx > DesignTokens.swipeVelocityThreshold {
            return .dismissPrevious
        }
        return .snapBack
    }

    /// Velocity-scaled throw distance and duration — fast short flicks stay visible longer.
    static func flyOutPlan(
        decision: Decision,
        translation: CGSize,
        velocity: CGSize,
        layoutWidth: CGFloat
    ) -> FlyOutPlan {
        let base = flyOutOffset(decision: decision, layoutWidth: layoutWidth)
        let alignedSpeed = alignedReleaseSpeed(
            decision: decision,
            translation: translation,
            velocity: velocity
        )
        let alignedDisplacement = alignedDragDistance(decision: decision, translation: translation)
        let excessSpeed = max(0, alignedSpeed - DesignTokens.swipeVelocityThreshold)
        let speedFactor = min(1, excessSpeed / DesignTokens.flyOutSpeedNormalization)
        let shortSwipeFactor = max(
            0,
            1 - alignedDisplacement / DesignTokens.swipeThreshold
        )
        let throwIntensity = min(
            1,
            speedFactor * 0.7 + shortSwipeFactor * speedFactor * 0.55 + shortSwipeFactor * 0.25
        )

        let projection = DesignTokens.swipeVelocityProjection
            + DesignTokens.flyOutVelocityProjectionBoost * throwIntensity
        var target = CGSize(
            width: base.width + velocity.width * projection,
            height: base.height + velocity.height * projection
        )

        let extraDistance = (
            DesignTokens.flyOutExtraDistanceBase
                + layoutWidth * DesignTokens.flyOutExtraDistanceLayoutFactor
        ) * throwIntensity
        switch decision {
        case .dismissNext:
            target.width -= extraDistance
        case .dismissPrevious:
            target.width += extraDistance
        case .dismissUp:
            target.height -= extraDistance
        case .snapBack:
            break
        }

        let duration = DesignTokens.flyOutDurationMin
            + (DesignTokens.flyOutDurationMax - DesignTokens.flyOutDurationMin)
            * (0.42 + 0.58 * throwIntensity)

        return FlyOutPlan(target: target, duration: duration)
    }

    static func projectedFlyOut(
        decision: Decision,
        translation: CGSize,
        velocity: CGSize,
        layoutWidth: CGFloat
    ) -> CGSize {
        flyOutPlan(
            decision: decision,
            translation: translation,
            velocity: velocity,
            layoutWidth: layoutWidth
        ).target
    }

    private static func alignedReleaseSpeed(
        decision: Decision,
        translation: CGSize,
        velocity: CGSize
    ) -> CGFloat {
        switch decision {
        case .dismissNext:
            return max(0, -velocity.width)
        case .dismissPrevious:
            return max(0, velocity.width)
        case .dismissUp:
            return max(0, -velocity.height)
        case .snapBack:
            return 0
        }
    }

    private static func alignedDragDistance(
        decision: Decision,
        translation: CGSize
    ) -> CGFloat {
        switch decision {
        case .dismissNext:
            return max(0, -translation.width)
        case .dismissPrevious:
            return max(0, translation.width)
        case .dismissUp:
            return max(0, -translation.height)
        case .snapBack:
            return 0
        }
    }

    static func flyOutOffset(decision: Decision, layoutWidth: CGFloat) -> CGSize {
        let overshoot = layoutWidth * 0.35 + DesignTokens.cardWidth
        switch decision {
        case .snapBack:
            return .zero
        case .dismissNext:
            return CGSize(width: -overshoot, height: 0)
        case .dismissPrevious:
            return CGSize(width: overshoot, height: 0)
        case .dismissUp:
            return CGSize(width: 0, height: -layoutWidth * 1.35)
        }
    }

    /// Continue drag rotation into the throw, capped at ±maxExitRotation.
    static func exitRotation(decision: Decision, currentRotation: Double) -> Double {
        switch decision {
        case .dismissNext:
            return min(currentRotation, -DesignTokens.maxExitRotation)
        case .dismissPrevious:
            return max(currentRotation, DesignTokens.maxExitRotation)
        case .dismissUp:
            return currentRotation * 0.35
        case .snapBack:
            return 0
        }
    }
}
