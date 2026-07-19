import Foundation

struct MahjongPlayerInput: Codable, Equatable, Sendable {
    var name: String
    var seat: String?
}

struct MahjongCreateRoomRequest: Codable, Equatable, Sendable {
    var deviceId: String
    var displayName: String
    var title: String
    var mode: MahjongRoomMode
    var startingScore: Int
    var players: [MahjongPlayerInput]
}

struct MahjongJoinRoomRequest: Codable, Equatable, Sendable {
    var deviceId: String
    var displayName: String
}

struct MahjongRoomDraft: Equatable, Sendable {
    static let maxPlayers = 20

    var deviceId: String
    var displayName: String
    var title: String
    var mode: MahjongRoomMode
    var playerNames: [String]

    func createRoomRequest() -> MahjongCreateRoomRequest {
        let fallbackNames = playerNames.isEmpty ? ["玩家1"] : playerNames
        let players = fallbackNames
            .prefix(Self.maxPlayers)
            .enumerated()
            .map { index, name in
                MahjongPlayerInput(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "玩家\(index + 1)" : name,
                    seat: nil
                )
            }

        return MahjongCreateRoomRequest(
            deviceId: deviceId,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "麻将计分" : title,
            mode: mode,
            startingScore: 0,
            players: players
        )
    }
}

enum MahjongRoomMode: String, Codable, CaseIterable, Equatable, Sendable {
    case multiplayer
    case solo

    var title: String {
        switch self {
        case .multiplayer:
            return "多人模式"
        case .solo:
            return "单人模式"
        }
    }
}

struct MahjongRoomSession: Codable, Equatable, Sendable {
    var roomCode: String
    var memberToken: String
    var isLocal: Bool = false
}

enum MahjongRoomConnectionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case online

    static let `default`: Self = .online
}

struct MahjongRoomResponse: Codable, Equatable, Sendable {
    var memberToken: String
    var snapshot: MahjongRoomSnapshot
}

struct MahjongRoomHistoryResponse: Codable, Equatable, Sendable {
    var rooms: [MahjongRoomInfo]
}

struct MahjongSettleRoomRequest: Codable, Equatable, Sendable {
    var multiplier: Double
}

struct MahjongSettleRoomResponse: Codable, Equatable, Sendable {
    var snapshot: MahjongRoomSnapshot
}

struct MahjongRoomSnapshot: Codable, Equatable, Sendable {
    var room: MahjongRoomInfo
    var players: [MahjongScorePlayer]
    var recentEvents: [MahjongScoreEvent]

    enum CodingKeys: String, CodingKey {
        case room, players, recentEvents
    }

    init(room: MahjongRoomInfo, players: [MahjongScorePlayer], recentEvents: [MahjongScoreEvent]) {
        self.room = room
        self.players = players
        self.recentEvents = recentEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room = try container.decode(MahjongRoomInfo.self, forKey: .room)
        players = try container.decodeIfPresent([MahjongScorePlayer].self, forKey: .players) ?? []
        recentEvents = try container.decodeIfPresent([MahjongScoreEvent].self, forKey: .recentEvents) ?? []
    }
}

struct MahjongRoomInfo: Codable, Equatable, Sendable {
    var id: String
    var code: String
    var title: String
    var status: String
    var mode: MahjongRoomMode
    var startingScore: Int
    var ownerDeviceId: String
    var multiplier: Double
    var createdAt: String
    var endedAt: String?
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, code, title, status, mode, startingScore, ownerDeviceId, multiplier, createdAt, endedAt, updatedAt
    }

    init(
        id: String,
        code: String,
        title: String,
        status: String,
        mode: MahjongRoomMode,
        startingScore: Int,
        ownerDeviceId: String,
        multiplier: Double,
        createdAt: String,
        endedAt: String?,
        updatedAt: String
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.status = status
        self.mode = mode
        self.startingScore = startingScore
        self.ownerDeviceId = ownerDeviceId
        self.multiplier = multiplier
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "麻将计分"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        mode = try container.decodeIfPresent(MahjongRoomMode.self, forKey: .mode) ?? .multiplayer
        startingScore = try Self.decodeFlexibleInt(container, forKey: .startingScore) ?? 0
        ownerDeviceId = try container.decodeIfPresent(String.self, forKey: .ownerDeviceId) ?? ""
        if let value = try container.decodeIfPresent(Double.self, forKey: .multiplier) {
            multiplier = value
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .multiplier) {
            multiplier = Double(value)
        } else {
            multiplier = 1
        }
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int? {
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try container.decodeIfPresent(String.self, forKey: key), let parsed = Int(value) {
            return parsed
        }
        return nil
    }
}

struct MahjongScorePlayer: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var deviceId: String?
    var seat: String?
    var score: Int
    var multiplierScore: Double
    var result: String?
    var sortOrder: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, deviceId, seat, score, multiplierScore, result, sortOrder, isActive
    }

    init(
        id: String,
        name: String,
        deviceId: String?,
        seat: String?,
        score: Int,
        multiplierScore: Double,
        result: String?,
        sortOrder: Int,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.seat = seat
        self.score = score
        self.multiplierScore = multiplierScore
        self.result = result
        self.sortOrder = sortOrder
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "玩家"
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        seat = try container.decodeIfPresent(String.self, forKey: .seat)
        score = try Self.decodeFlexibleInt(container, forKey: .score) ?? 0
        if let value = try container.decodeIfPresent(Double.self, forKey: .multiplierScore) {
            multiplierScore = value
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .multiplierScore) {
            multiplierScore = Double(value)
        } else {
            multiplierScore = Double(score)
        }
        result = try container.decodeIfPresent(String.self, forKey: .result)
        sortOrder = try Self.decodeFlexibleInt(container, forKey: .sortOrder) ?? 0
        if let value = try container.decodeIfPresent(Bool.self, forKey: .isActive) {
            isActive = value
        } else if let value = try Self.decodeFlexibleInt(container, forKey: .isActive) {
            isActive = value != 0
        } else {
            isActive = true
        }
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int? {
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try container.decodeIfPresent(String.self, forKey: key), let parsed = Int(value) {
            return parsed
        }
        return nil
    }
}

struct MahjongScoreEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var playerId: String
    var actorMemberId: String
    var delta: Int
    var reason: String?
    var scoreAfter: Int
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, playerId, actorMemberId, delta, reason, scoreAfter, createdAt
    }

    init(
        id: String,
        playerId: String,
        actorMemberId: String,
        delta: Int,
        reason: String?,
        scoreAfter: Int,
        createdAt: String
    ) {
        self.id = id
        self.playerId = playerId
        self.actorMemberId = actorMemberId
        self.delta = delta
        self.reason = reason
        self.scoreAfter = scoreAfter
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        playerId = try container.decodeIfPresent(String.self, forKey: .playerId) ?? ""
        actorMemberId = try container.decodeIfPresent(String.self, forKey: .actorMemberId) ?? ""
        delta = try container.decodeIfPresent(Int.self, forKey: .delta) ?? 0
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        scoreAfter = try container.decodeIfPresent(Int.self, forKey: .scoreAfter) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

enum MahjongRecentTableFormatter {
    static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.date(from: value)
    }

    static func formatStart(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
