import Foundation
import UserNotifications

enum NotificationPermissionNextStep: Equatable, Sendable {
    case request
    case openSettings
    case finish
}

struct NotificationPermissionCompletionGate: Equatable, Sendable {
    private(set) var hasFinished = false

    mutating func claim() -> Bool {
        guard !hasFinished else { return false }
        hasFinished = true
        return true
    }
}

enum NotificationPermissionStore {
    private static let deferredAtKey = "party-games.notification.deferred-at"
    private static let completedKey = "party-games.notification.prompt-completed"
    private static let reaskInterval: TimeInterval = 7 * 24 * 60 * 60

    static var shouldShowPrompt: Bool {
        if UserDefaults.standard.bool(forKey: completedKey) {
            return false
        }
        if let deferredAt = UserDefaults.standard.object(forKey: deferredAtKey) as? Date {
            return Date().timeIntervalSince(deferredAt) >= reaskInterval
        }
        return true
    }

    static func markDeferred() {
        UserDefaults.standard.set(Date(), forKey: deferredAtKey)
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: deferredAtKey)
    }

    static func nextStep(for status: UNAuthorizationStatus) -> NotificationPermissionNextStep {
        switch status {
        case .notDetermined:
            return .request
        case .denied:
            return .openSettings
        case .authorized, .provisional, .ephemeral:
            return .finish
        @unknown default:
            return .openSettings
        }
    }

    static func refreshSystemAuthorizationAndCompleteIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            markCompleted()
        default:
            break
        }
    }
}
