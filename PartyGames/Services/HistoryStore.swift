import Foundation

enum HistoryStore {
    private static let storageKey = "party-game-history"
    static let maxCount = 20

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ ids: [String]) {
        let trimmed = Array(ids.prefix(maxCount))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func prepend(_ gameId: String, to ids: inout [String]) {
        ids.removeAll { $0 == gameId }
        ids.insert(gameId, at: 0)
        ids = Array(ids.prefix(maxCount))
        save(ids)
    }
}
