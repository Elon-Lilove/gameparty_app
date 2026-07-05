import UIKit

enum HapticService {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
