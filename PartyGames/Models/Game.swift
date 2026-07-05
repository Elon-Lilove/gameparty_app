import Foundation

/// Core game model — mirrors React `interface Game` in App.tsx.
struct Game: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var players: PlayerOption
    var playerMin: Int?
    var playerMax: Int?
    var type: GameType
    var tags: [String]
    var rules: [String]
    var voiceScript: [String]
    var cardDescription: String?
    var badge: String?
    var duration: String?
    var detailIntro: String?
    var preparation: [String]?
    var startButtonLabel: String?

    // MARK: - Derived helpers (ported from FeaturedGameCard / App.tsx)

    var playerLabel: String {
        if let min = playerMin, let max = playerMax {
            return min == max ? "\(min)人" : "\(min)-\(max)人"
        }
        switch players {
        case .two: return "2人"
        case .threeToFour: return "3-6人"
        case .fivePlus: return "5人以上"
        }
    }

    var displayBadge: String {
        if let badge, !badge.trimmingCharacters(in: .whitespaces).isEmpty {
            return badge.trimmingCharacters(in: .whitespaces)
        }
        if tags.contains("party") || tags.contains("icebreaker") { return "派对爆笑" }
        if tags.contains("classic") { return "经典必玩" }
        if tags.contains("mind game") { return "烧脑对决" }
        return "热门推荐"
    }

    var displayDuration: String {
        if let duration, !duration.isEmpty { return duration }
        return Game.defaultDurations[id] ?? "10-15分钟"
    }

    var firstRuleLine: String {
        rules.first ?? ""
    }

    func matchesMood(_ mood: MoodCategory) -> Bool {
        guard mood != .all else { return true }
        return mood.matchingTags.contains { tags.contains($0) }
    }

    func matchesPlayerCount(_ count: Int) -> Bool {
        if let min = playerMin, let max = playerMax {
            return count >= min && count <= max
        }
        switch players {
        case .two: return count == 2
        case .threeToFour: return count >= 3 && count <= 4
        case .fivePlus: return count >= 5
        }
    }
}

extension Game {
    /// Duration lookup from FeaturedGameCard GAME_DURATION.
    static let defaultDurations: [String: String] = [
        "true_or_false": "10-15分钟",
        "seven_pass": "15-20分钟",
        "watermelon": "10-15分钟",
        "number_bomb": "10-15分钟",
        "brain_twist": "10-15分钟",
        "finger_guess": "5-10分钟",
        "truth_dare": "20-30分钟",
        "never_have_i": "15-25分钟",
        "who_most": "15-20分钟",
        "category_drink": "10-20分钟",
        "song_chain": "15-25分钟",
        "telephone": "10-15分钟",
        "describe_guess": "15-20分钟",
    ]
}

/// Lightweight featured-game projection (React FeaturedGame interface).
typealias FeaturedGame = Game

extension Game {
  static let sampleGames: [Game] = [
    Game(
      id: "true_or_false",
      name: "真真假假",
      players: .threeToFour,
      playerMin: 2,
      playerMax: 8,
      type: .noProps,
      tags: ["icebreaker", "social"],
      rules: [
        "每位玩家轮流说三句话。",
        "其中一句必须是假的。",
        "其他人猜哪一句是假话。",
      ],
      voiceScript: [
        "游戏开始。",
        "本局是真真假假。",
        "适合二到八位玩家。",
        "每位玩家轮流说三句话，其中一句必须是假的。",
        "其他人猜出哪一句是假话。",
        "现在可以开始。",
      ],
      duration: "5分钟"
    ),
    Game(
      id: "seven_pass",
      name: "逢7必过",
      players: .fivePlus,
      type: .noProps,
      tags: ["reaction", "focus"],
      rules: [
        "从一开始依次报数。",
        "遇到七的倍数或含七的数字时拍手。",
        "说错或拍错的人接受惩罚。",
      ],
      voiceScript: [
        "游戏开始。",
        "本局是逢七必过。",
        "适合五人以上。",
        "大家依次报数，遇到七的倍数或含七的数字时不要说数字，改为拍手。",
        "说错或拍错的人接受惩罚。",
        "现在开始。",
      ]
    ),
    Game(
      id: "watermelon",
      name: "大西瓜小西瓜",
      players: .fivePlus,
      type: .noProps,
      tags: ["reaction", "party"],
      rules: [
        "主持人说大西瓜或小西瓜。",
        "说大西瓜时做小手势。",
        "说小西瓜时做大手势。",
      ],
      voiceScript: [
        "游戏开始。",
        "本局是大西瓜小西瓜。",
        "主持人随机喊大西瓜或小西瓜。",
        "动作要和听到的内容相反。",
        "做错的人接受挑战。",
        "现在开始。",
      ]
    ),
  ]
}
