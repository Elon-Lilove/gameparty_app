import Foundation

/// Scorekeeper player — mirrors React `interface ScorePlayer` in App.tsx.
struct ScorePlayer: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var score: Int

    static let defaults: [ScorePlayer] = [
        ScorePlayer(id: "p1", name: "玩家 1", score: 0),
        ScorePlayer(id: "p2", name: "玩家 2", score: 0),
    ]
}
