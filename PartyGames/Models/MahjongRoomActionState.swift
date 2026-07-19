import Foundation

enum MahjongRoomPendingAction: Equatable, Sendable {
    case adjustScore(playerId: String, operationId: String)
    case addPlayer(operationId: String)
    case giveScore(targetPlayerId: String, operationId: String)
    case tableScore(operationId: String)
    case rename(playerId: String, operationId: String)
    case removePlayer(playerId: String, operationId: String)
    case transferOwner(targetDeviceId: String, operationId: String)

    var operationId: String {
        switch self {
        case .adjustScore(_, let operationId),
             .addPlayer(let operationId),
             .giveScore(_, let operationId),
             .tableScore(let operationId),
             .rename(_, let operationId),
             .removePlayer(_, let operationId),
             .transferOwner(_, let operationId):
            return operationId
        }
    }

    var progressText: String {
        switch self {
        case .adjustScore:
            return "计分提交中"
        case .addPlayer:
            return "添加中"
        case .giveScore:
            return "给分中"
        case .tableScore:
            return "台板计分中"
        case .rename:
            return "改名中"
        case .removePlayer:
            return "正在退出"
        case .transferOwner:
            return "转让中"
        }
    }
}

struct MahjongRoomActionState: Equatable, Sendable {
    private(set) var pending: MahjongRoomPendingAction?

    @discardableResult
    mutating func begin(_ action: MahjongRoomPendingAction) -> Bool {
        guard pending == nil else { return false }
        pending = action
        return true
    }

    @discardableResult
    mutating func complete(operationId: String) -> Bool {
        guard pending?.operationId == operationId else { return false }
        pending = nil
        return true
    }

    @discardableResult
    mutating func fail(operationId: String) -> Bool {
        complete(operationId: operationId)
    }

    mutating func cancel() {
        pending = nil
    }
}
