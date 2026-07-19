import Foundation
import XCTest
@testable import PartyGames

final class MahjongScoreServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSettleRoomPostsMultiplierToSettleRoute() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let service = MahjongScoreService(baseURL: URL(string: "https://worker.test")!, session: session)

        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/rooms/ABC123/settle")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer member-token")
            let body = try XCTUnwrap(request.httpBody)
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Double]
            XCTAssertEqual(payload?["multiplier"], 2)

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                #"{"snapshot":{"room":{"id":"room-1","code":"ABC123","title":"麻将计分","status":"ended","mode":"multiplayer","startingScore":0,"ownerDeviceId":"owner-device","multiplier":2,"createdAt":"2026-07-13 12:00:00","endedAt":"2026-07-13 12:10:00","updatedAt":"2026-07-13 12:10:00"},"players":[],"recentEvents":[]}}"#.utf8
            )
            return (response, data)
        }

        let result = try await service.settleRoom(code: "abc123", memberToken: "member-token", multiplier: 2)

        XCTAssertEqual(result.snapshot.room.status, "ended")
        XCTAssertEqual(result.snapshot.room.multiplier, 2)
    }
}
