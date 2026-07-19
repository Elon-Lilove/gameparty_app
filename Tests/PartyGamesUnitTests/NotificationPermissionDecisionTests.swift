import UserNotifications
import XCTest
@testable import PartyGames

final class NotificationPermissionDecisionTests: XCTestCase {
    func testMapsSystemAuthorizationToOneEffectiveNextStep() {
        XCTAssertEqual(NotificationPermissionStore.nextStep(for: .notDetermined), .request)
        XCTAssertEqual(NotificationPermissionStore.nextStep(for: .denied), .openSettings)
        XCTAssertEqual(NotificationPermissionStore.nextStep(for: .authorized), .finish)
        XCTAssertEqual(NotificationPermissionStore.nextStep(for: .provisional), .finish)
        XCTAssertEqual(NotificationPermissionStore.nextStep(for: .ephemeral), .finish)
    }
}
