import SwiftUI
import UIKit

struct SwipeCardFlyOutSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
    let decision: CardSwipePhysics.Decision
    let cardSize: CGSize
    let startOffset: CGSize
    let targetOffset: CGSize
    let startRotation: Double
    let targetRotation: Double
    let startScale: CGFloat
    let targetScale: CGFloat
    let duration: Double
}

@MainActor
struct SwipeCardSnapshotAnimator: UIViewRepresentable {
    let snapshot: SwipeCardFlyOutSnapshot
    let onComplete: @MainActor (UUID, CardSwipePhysics.Decision) -> Void

    typealias UIViewType = SnapshotAnimationContainerView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SnapshotAnimationContainerView {
        let view = SnapshotAnimationContainerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SnapshotAnimationContainerView, context: Context) {
        context.coordinator.animate(snapshot, in: uiView, onComplete: onComplete)
    }

    @MainActor
    final class Coordinator {
        private var animatedID: UUID?
        private var animator: UIViewPropertyAnimator?
        private weak var imageView: UIImageView?

        func animate(
            _ snapshot: SwipeCardFlyOutSnapshot,
            in container: SnapshotAnimationContainerView,
            onComplete: @escaping @MainActor (UUID, CardSwipePhysics.Decision) -> Void
        ) {
            guard animatedID != snapshot.id else { return }
            guard container.bounds.width > 0, container.bounds.height > 0 else {
                container.onBoundsReady = { [weak self, weak container] in
                    guard let self, let container else { return }
                    self.animate(snapshot, in: container, onComplete: onComplete)
                }
                return
            }

            animator?.stopAnimation(true)
            imageView?.removeFromSuperview()
            animatedID = snapshot.id

            let imageView = UIImageView(image: snapshot.image)
            imageView.bounds = CGRect(origin: .zero, size: snapshot.cardSize)
            imageView.center = CGPoint(
                x: container.bounds.midX + snapshot.startOffset.width,
                y: snapshot.cardSize.height / 2 + snapshot.startOffset.height
            )
            imageView.contentMode = .scaleAspectFill
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.12
            imageView.layer.shadowRadius = 18
            imageView.layer.shadowOffset = CGSize(width: 0, height: 10)
            imageView.layer.transform = transform(
                rotation: snapshot.startRotation,
                scale: snapshot.startScale
            )
            container.addSubview(imageView)
            self.imageView = imageView

            let timing = UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.18, y: 0.72),
                controlPoint2: CGPoint(x: 0.22, y: 1)
            )
            let animator = UIViewPropertyAnimator(
                duration: snapshot.duration,
                timingParameters: timing
            )
            animator.addAnimations {
                imageView.center = CGPoint(
                    x: container.bounds.midX + snapshot.targetOffset.width,
                    y: snapshot.cardSize.height / 2 + snapshot.targetOffset.height
                )
                imageView.layer.transform = self.transform(
                    rotation: snapshot.targetRotation,
                    scale: snapshot.targetScale
                )
                imageView.alpha = 1
            }
            animator.addCompletion { [weak imageView] _ in
                imageView?.removeFromSuperview()
                onComplete(snapshot.id, snapshot.decision)
            }
            self.animator = animator
            animator.startAnimation()
        }

        private func transform(rotation: Double, scale: CGFloat) -> CATransform3D {
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 900
            transform = CATransform3DRotate(
                transform,
                CGFloat(rotation * 0.55) * .pi / 180,
                0,
                1,
                0
            )
            transform = CATransform3DRotate(
                transform,
                CGFloat(rotation) * .pi / 180,
                0,
                0,
                1
            )
            transform = CATransform3DScale(transform, scale, scale, 1)
            return transform
        }
    }
}

@MainActor
final class SnapshotAnimationContainerView: UIView {
    var onBoundsReady: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let onBoundsReady = onBoundsReady
        self.onBoundsReady = nil
        onBoundsReady?()
    }
}
