import Foundation

@main
enum MahjongRoomActionStateTest {
    static func main() {
        var state = MahjongRoomActionState()
        let action = MahjongRoomPendingAction.giveScore(targetPlayerId: "guest", operationId: "op-1")

        precondition(state.begin(action))
        precondition(!state.begin(.tableScore(operationId: "op-2")))
        precondition(state.pending == action)

        precondition(!state.complete(operationId: "other"))
        precondition(state.pending == action)

        precondition(state.complete(operationId: "op-1"))
        precondition(state.pending == nil)

        precondition(state.begin(.rename(playerId: "guest", operationId: "op-3")))
        precondition(state.fail(operationId: "op-3"))
        precondition(state.pending == nil)
    }
}
