import XCTest
import PrivySDK
@testable import BSmart

@MainActor
final class EmbeddedWalletLookupTests: XCTestCase {
    private let address = "0x" + String(repeating: "a", count: 40)

    func testFreshNewAccountCanCreateEvenWhenRefreshWouldBeRateLimited() async throws {
        let inventory = InventoryDouble()
        inventory.refreshError = ApiError.apiError(httpCode: 429, errorCode: "rate_limit", description: "private")
        inventory.createdAddress = address
        let probe = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: nil, create: false, reconcileCreation: false)
        XCTAssertNil(probe)
        let created = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: nil, create: true, reconcileCreation: false)
        XCTAssertEqual(created, address)
        XCTAssertEqual(inventory.refreshes, 0)
        XCTAssertEqual(inventory.creates, 1)
    }

    func testRegisteredWalletReusesAuthenticatedInventoryWithoutRefresh() async throws {
        let inventory = InventoryDouble()
        inventory.addresses = [address]
        let found = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: address, create: false, reconcileCreation: false)
        XCTAssertEqual(found, address)
        XCTAssertEqual(inventory.refreshes, 0)
        XCTAssertEqual(inventory.creates, 0)
    }

    func testMissingRegisteredAddressRefreshesOnceAndNeverCreatesReplacement() async throws {
        let inventory = InventoryDouble()
        let found = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: address, create: true, reconcileCreation: false)
        XCTAssertNil(found)
        XCTAssertEqual(inventory.refreshes, 1)
        XCTAssertEqual(inventory.creates, 0)
    }

    func testUncertainCreationFindsExistingWalletBeforeAnyNewCreate() async throws {
        let inventory = InventoryDouble()
        inventory.afterRefresh = [address]
        let found = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: nil, create: true, reconcileCreation: true)
        XCTAssertEqual(found, address)
        XCTAssertEqual(inventory.refreshes, 1)
        XCTAssertEqual(inventory.creates, 0)
    }

    func testFailedReconciliationDoesNotCreateAndMultipleWalletsAreNotGuessed() async throws {
        let inventory = InventoryDouble()
        inventory.refreshError = EmbeddedWalletError.rateLimited(seconds: 60)
        await expectJournalFailure {
            try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: nil, create: true, reconcileCreation: true)
        }
        XCTAssertEqual(inventory.creates, 0)
        inventory.addresses = [address, "0x" + String(repeating: "b", count: 40)]
        await expectJournalFailure {
            try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: nil, create: true, reconcileCreation: false)
        }
        XCTAssertEqual(inventory.creates, 0)
    }

    func testRateLimitBackoffIsBoundedAndDoesNotClearOnEarlyRetry() {
        var backoff = EmbeddedWalletBackoff()
        let now = ContinuousClock.now
        XCTAssertEqual(backoff.remaining(at: now), 0)
        XCTAssertEqual(backoff.limited(at: now), 60)
        XCTAssertEqual(backoff.remaining(at: now.advanced(by: .seconds(20))), 40)
        XCTAssertEqual(backoff.remaining(at: now.advanced(by: .seconds(60))), 0)
        XCTAssertEqual(backoff.limited(at: now.advanced(by: .seconds(60))), 120)
        XCTAssertEqual(backoff.limited(at: now), 240)
        XCTAssertEqual(backoff.limited(at: now), 300)
        XCTAssertEqual(backoff.limited(at: now), 300)
        backoff.succeeded()
        XCTAssertEqual(backoff.remaining(at: now), 0)
        XCTAssertEqual(backoff.limited(at: now), 60)
    }
}

@MainActor
private final class InventoryDouble: EmbeddedWalletInventory {
    var addresses = [String]()
    var afterRefresh = [String]()
    var refreshError: Error?
    var createdAddress = ""
    var refreshes = 0
    var creates = 0
    func refresh() async throws {
        refreshes += 1
        if let refreshError { throw refreshError }
        addresses = afterRefresh
    }
    func create() async throws -> String {
        creates += 1
        addresses = [createdAddress]
        return createdAddress
    }
}
