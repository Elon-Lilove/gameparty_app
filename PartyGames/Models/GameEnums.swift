import Foundation

// MARK: - Player & game type (mirrors React App.tsx)

enum PlayerOption: String, Codable, CaseIterable, Sendable {
    case two = "2"
    case threeToFour = "3-4"
    case fivePlus = "5+"

    var label: String {
        switch self {
        case .two: return "2人"
        case .threeToFour: return "3-4人"
        case .fivePlus: return "5人以上"
        }
    }
}

enum GameType: String, Codable, CaseIterable, Sendable {
    case noProps = "No Props"
    case drinking = "Drinking"
    case dice = "Dice"

    var labelZh: String {
        switch self {
        case .noProps: return "无道具"
        case .drinking: return "酒桌向"
        case .dice: return "骰子类"
        }
    }

    var emoji: String {
        switch self {
        case .noProps: return "⚡"
        case .drinking: return "🍹"
        case .dice: return "🎲"
        }
    }
}

enum MoodCategory: String, Codable, CaseIterable, Sendable {
    case all
    case funny
    case flirty
    case brain
    case icebreaker

    var emoji: String {
        switch self {
        case .all: return "🎲"
        case .funny: return "🤩"
        case .flirty: return "💗"
        case .brain: return "🧠"
        case .icebreaker: return "🧊"
        }
    }

    var label: String {
        switch self {
        case .all: return "随便玩"
        case .funny: return "想笑"
        case .flirty: return "想暧昧"
        case .brain: return "想动脑"
        case .icebreaker: return "想破冰"
        }
    }

    /// Tags used for mood filtering (from React MOOD_TAG_MAP).
    var matchingTags: [String] {
        switch self {
        case .all: return []
        case .funny: return ["icebreaker", "party", "reaction"]
        case .flirty: return ["confession", "social", "truth"]
        case .brain: return ["mind game", "guessing", "focus", "classic"]
        case .icebreaker: return ["icebreaker", "warm", "social"]
        }
    }
}

enum HomeTab: String, CaseIterable, Hashable, Sendable {
    case home
    case library
    case tools
    case me
}

enum DeckMotion: String, Sendable {
    case idle
    case exitUp = "exit-up"
    case exitLeft = "exit-left"
    case exitRight = "exit-right"
    case enterNext = "enter-next"
    case enterPrev = "enter-prev"
}

enum SpinPhase: String, Sendable {
    case idle
    case press
    case accelerate
    case chaos
    case decelerate
    case settle
}

enum MyPanelScreen: String, Sendable {
    case menu
    case favorites
    case admin
}

// MARK: - Tag labels (subset from React TAG_LABEL)

enum GameTag: String, Sendable {
    case icebreaker, social, reaction, focus, party
    case mindGame = "mind game"
    case tension, quickThinking = "quick thinking", duel, guessing, classic
    case confession, voting, memory, speed, music, communication, chaos
    case creative, random, truth, challenge, host, quick, story, drinking
    case topic, acting, warm, vote

    var labelZh: String {
        switch self {
        case .icebreaker: return "破冰"
        case .social: return "社交"
        case .reaction: return "反应"
        case .focus: return "专注"
        case .party: return "派对"
        case .mindGame: return "心理"
        case .tension: return "紧张"
        case .quickThinking: return "快问"
        case .duel: return "对战"
        case .guessing: return "猜谜"
        case .classic: return "经典"
        case .confession: return "坦白"
        case .voting: return "投票"
        case .memory: return "记忆"
        case .speed: return "速度"
        case .music: return "音乐"
        case .communication: return "传话"
        case .chaos: return "混乱"
        case .creative: return "创意"
        case .random: return "随机"
        case .truth: return "真心话"
        case .challenge: return "挑战"
        case .host: return "主持"
        case .quick: return "快节奏"
        case .story: return "故事"
        case .drinking: return "饮酒"
        case .topic: return "话题"
        case .acting: return "表演"
        case .warm: return "暖场"
        case .vote: return "站队"
        }
    }

    static func label(for tag: String) -> String {
        GameTag(rawValue: tag)?.labelZh ?? tag
    }
}
