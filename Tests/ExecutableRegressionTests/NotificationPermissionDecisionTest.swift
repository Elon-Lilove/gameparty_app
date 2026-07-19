import Foundation
import UserNotifications

@main
enum NotificationPermissionDecisionTest {
    static func main() {
        precondition(NotificationPermissionStore.nextStep(for: .notDetermined) == .request)
        precondition(NotificationPermissionStore.nextStep(for: .denied) == .openSettings)
        precondition(NotificationPermissionStore.nextStep(for: .authorized) == .finish)
        precondition(NotificationPermissionStore.nextStep(for: .provisional) == .finish)
#if os(iOS)
        precondition(NotificationPermissionStore.nextStep(for: .ephemeral) == .finish)
#endif

        var completionGate = NotificationPermissionCompletionGate()
        precondition(completionGate.claim())
        precondition(!completionGate.claim())
    }
}
