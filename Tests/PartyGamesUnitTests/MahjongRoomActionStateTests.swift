import XCTest
@testable import PartyGames

final class MahjongRoomActionStateTests: XCTestCase {
    func testMatchingAcknowledgementClearsPendingAction() {
        var state = MahjongRoomActionState()
        XCTAssertTrue(state.begin(.giveScore(targetPlayerId: "guest", operationId: "op-1")))

        XCTAssertTrue(state.complete(operationId: "op-1"))
        XCTAssertNil(state.pending)
    }

    func testDifferentAcknowledgementDoesNotClearPendingAction() {
        var state = MahjongRoomActionState()
        XCTAssertTrue(state.begin(.giveScore(targetPlayerId: "guest", operationId: "op-1")))

        XCTAssertFalse(state.complete(operationId: "other"))
        XCTAssertNotNil(state.pending)
    }

    func testSecondActionIsRejectedWhileFirstIsPending() {
        var state = MahjongRoomActionState()
        XCTAssertTrue(state.begin(.tableScore(operationId: "op-1")))

        XCTAssertFalse(state.begin(.rename(playerId: "owner", operationId: "op-2")))
        XCTAssertEqual(state.pending, .tableScore(operationId: "op-1"))
    }
}
