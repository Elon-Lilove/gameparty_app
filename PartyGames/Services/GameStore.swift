import Foundation

enum GameStore {
    private static let storageKey = "party-games"

    static func load() -> [Game] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Game].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return loadDefaults()
    }

    static func save(_ games: [Game]) {
        guard let data = try? JSONEncoder().encode(games) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func loadDefaults() -> [Game] {
        guard let url = Bundle.module.url(forResource: "default_games", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([Game].self, from: data),
              !games.isEmpty else {
            return Game.sampleGames
        }
        return games
    }
}
