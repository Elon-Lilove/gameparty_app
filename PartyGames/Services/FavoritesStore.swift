import Foundation

enum FavoritesStore {
    private static let storageKey = "party-favorites"

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func toggle(_ gameId: String, in ids: inout [String]) {
        if let index = ids.firstIndex(of: gameId) {
            ids.remove(at: index)
        } else {
            ids.append(gameId)
        }
        save(ids)
    }

    static func isFavorite(_ gameId: String, in ids: [String]) -> Bool {
        ids.contains(gameId)
    }
}
