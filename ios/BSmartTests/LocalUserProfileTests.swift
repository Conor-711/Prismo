import XCTest
@testable import BSmart

@MainActor
final class LocalUserProfileTests: XCTestCase {
    func testPersistenceAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalUserProfileStore(directory: directory)
        store.load(accountID: nil)
        try store.save(.init(nickname: "  Casey  ", bio: "Research", avatarData: Data([1, 2])), expectedScope: "guest")
        let restored = LocalUserProfileStore(directory: directory)
        restored.load(accountID: nil)
        XCTAssertEqual(restored.profile.nickname, "Casey")
        XCTAssertEqual(restored.profile.avatarData, Data([1, 2]))
        let accountID = UUID()
        restored.load(accountID: accountID)
        XCTAssertEqual(restored.profile.nickname, "")
        XCTAssertThrowsError(try restored.save(.init(nickname: "Wrong account"), expectedScope: "guest"))
        try restored.save(.init(nickname: "Morgan"), expectedScope: restored.scope)
        restored.load(accountID: nil)
        XCTAssertEqual(restored.profile.nickname, "Casey")
        restored.load(accountID: accountID)
        XCTAssertEqual(restored.profile.nickname, "Morgan")
    }

    func testBoundsAndFailedSavePreserveProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalUserProfileStore(directory: directory)
        try store.save(.init(nickname: String(repeating: "a", count: 40), bio: String(repeating: "b", count: 150)), expectedScope: "guest")
        XCTAssertEqual(store.profile.nickname.count, 28)
        XCTAssertEqual(store.profile.bio.count, 120)
        let before = store.profile
        XCTAssertThrowsError(try store.save(.init(avatarData: Data(count: 200_001)), expectedScope: "guest"))
        XCTAssertEqual(store.profile, before)
    }

    func testAddressRequiresMatchingVerifiedWallet() {
        let accountID = UUID()
        let address = "0x1234567890123456789012345678901234567890"
        let wallet = DeviceWalletState.verified(.init(accountID: accountID, address: address, recoveryVerified: false))
        XCTAssertEqual(ProfileAddress(accountID: accountID, wallet: wallet).value, address)
        XCTAssertFalse(ProfileAddress(accountID: accountID, wallet: wallet).isExample)
        for state in [DeviceWalletState.locked, .loading, .recoveryRequired(address: address), wallet] {
            XCTAssertTrue(ProfileAddress(accountID: nil, wallet: state).isExample)
        }
        XCTAssertTrue(ProfileAddress(accountID: UUID(), wallet: wallet).isExample)
        XCTAssertEqual(ProfileAddress(accountID: accountID, wallet: .locked).value, ProfileAddress.example)
    }

    func testErasureBlocksStaleEditorAndPreservesOtherAccountsAndGuest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalUserProfileStore(directory: directory)
        let target = UUID(), other = UUID()
        for id in [nil, target, other] {
            store.load(accountID: id)
            try store.save(.init(nickname: "Saved", bio: "Private", avatarData: Data([1, 2])), expectedScope: store.scope)
        }
        let stale = LocalUserProfileStore(directory: directory)
        stale.load(accountID: target)
        let draft = stale.profile
        try store.erase(accountID: target)
        try store.erase(accountID: target)
        XCTAssertThrowsError(try stale.save(draft, expectedScope: stale.scope))
        stale.load(accountID: target)
        XCTAssertEqual(stale.profile, LocalUserProfile())
        let path = directory.appendingPathComponent(target.uuidString.lowercased()).appendingPathExtension("json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        for id in [nil, other] {
            store.load(accountID: id)
            XCTAssertEqual(store.profile.nickname, "Saved")
            XCTAssertEqual(store.profile.avatarData, Data([1, 2]))
        }
    }
}
