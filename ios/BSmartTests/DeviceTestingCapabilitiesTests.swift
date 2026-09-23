import XCTest
@testable import BSmart

@MainActor
final class DeviceTestingCapabilitiesTests: XCTestCase {
    func testBuildEnablesAppleSignInAndPush() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BSMART_APPLE_SIGN_IN_ENABLED") as? String, "YES")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BSMART_PUSH_ENABLED") as? String, "YES")
        XCTAssertTrue(NotificationService.isEnabled)
        XCTAssertTrue(AccountIdentityAuthorizer.isAppleSignInEnabled)
    }

    func testPushRegistrationUsesBuildEnvironment() {
        let environment = Bundle.main.object(forInfoDictionaryKey: "BSMART_APNS_ENVIRONMENT") as? String
        XCTAssertTrue(["development", "production"].contains(environment))
        XCTAssertEqual(ContentPushDevice.environment(), environment)
    }
}
