import Foundation

enum ScoreStore {
    private static let key = "party-games-score-players"

    static func load() -> [ScorePlayer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let players = try? JSONDecoder().decode([ScorePlayer].self, from: data),
              !players.isEmpty else {
            return [
                ScorePlayer(id: "p1", name: "玩家 1", score: 0),
                ScorePlayer(id: "p2", name: "玩家 2", score: 0),
            ]
        }
        return players
    }

    static func save(_ players: [ScorePlayer]) {
        guard let data = try? JSONEncoder().encode(players) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
