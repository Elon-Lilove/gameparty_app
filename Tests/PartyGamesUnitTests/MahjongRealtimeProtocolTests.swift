import Foundation
import XCTest
@testable import PartyGames

final class MahjongRealtimeProtocolTests: XCTestCase {
    func testErrorEnvelopeDecodesMatchingOperationAcknowledgement() throws {
        let data = Data(
            #"{"type":"error","error":"Use give_score","operationId":"invalid-score","actorDeviceId":"guest-device"}"#.utf8
        )

        let envelope = try JSONDecoder().decode(MahjongRealtimeEnvelope.self, from: data)

        XCTAssertEqual(envelope.type, "error")
        XCTAssertEqual(envelope.error, "Use give_score")
        XCTAssertEqual(
            envelope.acknowledgement,
            MahjongRealtimeAcknowledgement(operationId: "invalid-score", actorDeviceId: "guest-device")
        )
    }
}
