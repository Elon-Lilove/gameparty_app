import Foundation

struct MahjongRealtimeAcknowledgement: Equatable, Sendable {
    var operationId: String
    var actorDeviceId: String?
}

struct MahjongRealtimeEnvelope: Decodable, Sendable {
    var type: String
    var snapshot: MahjongRoomSnapshot?
    var error: String?
    var operationId: String?
    var actorDeviceId: String?

    var acknowledgement: MahjongRealtimeAcknowledgement? {
        guard let operationId, !operationId.isEmpty else { return nil }
        return MahjongRealtimeAcknowledgement(operationId: operationId, actorDeviceId: actorDeviceId)
    }
}

struct MahjongRealtimeMessage: Encodable, Sendable {
    var type: String
    var playerId: String?
    var delta: Int?
    var reason: String?
    var name: String?
    var targetDeviceId: String?
    var targetPlayerId: String?
    var amount: Int?
    var operationId: String?
}
