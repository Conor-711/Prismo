import XCTest
@testable import BSmart

final class SmartMoneyPublicIdentityTests: XCTestCase {
    func testAddressProducesStableCrossPlatformAlias() {
        let identity = SmartMoneyPublicIdentity.resolve(
            identityKey: "0x89c0fee4b7ca37711219092cd1c0d2b4f7af87c1",
            displayName: nil,
            avatarVariant: nil
        )

        XCTAssertEqual(identity.displayName, "Isla")
        XCTAssertEqual(identity.avatarVariant, 54)
    }

    func testContractIdentityOverridesFallback() {
        let identity = SmartMoneyPublicIdentity.resolve(
            identityKey: "0x1234",
            displayName: "Maya",
            avatarVariant: 3
        )

        XCTAssertEqual(identity.displayName, "Maya")
        XCTAssertEqual(identity.avatarVariant, 3)
    }
}
