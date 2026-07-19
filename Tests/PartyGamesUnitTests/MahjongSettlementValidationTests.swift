import XCTest
@testable import PartyGames

final class MahjongSettlementValidationTests: XCTestCase {
    func testAcceptsMultiplierInsideAllowedRange() throws {
        XCTAssertEqual(try MahjongSettlementValidation.parse("2").get(), 2)
        XCTAssertEqual(try MahjongSettlementValidation.parse(" 1.5 ").get(), 1.5)
    }

    func testRejectsMissingInvalidAndOutOfRangeMultiplier() {
        for raw in ["", "0", "-1", "1000001", "abc"] {
            XCTAssertThrowsError(try MahjongSettlementValidation.parse(raw).get(), "Expected \(raw) to fail")
        }
    }
}
