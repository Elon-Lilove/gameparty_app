import Foundation

enum MahjongMemberTokenStore {
    private static let keyPrefix = "party-games.mahjong.member-token."

    static func token(for roomCode: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(for: roomCode))
    }

    static func save(_ token: String, for roomCode: String, defaults: UserDefaults = .standard) {
        defaults.set(token, forKey: key(for: roomCode))
    }

    static func remove(for roomCode: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: roomCode))
    }

    private static func key(for roomCode: String) -> String {
        keyPrefix + roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
