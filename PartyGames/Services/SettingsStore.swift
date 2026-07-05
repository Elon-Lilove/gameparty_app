import Foundation

enum SettingsStore {
    private static let membershipBoxKey = "partyGames.membershipBoxEnabled"

    static var membershipBoxEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: membershipBoxKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: membershipBoxKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: membershipBoxKey)
        }
    }
}
