import XCTest
import WalletCore
@testable import BSmart

final class CCTPDepositCodecTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private let wallet = DeviceWalletSummary(accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf", recoveryVerified: true)

    func testTypedDataMatchesIndependentEthereumImplementation() throws {
        let vector = try fixture()
        let plan = try makePlan()
        let json = try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet, now: now)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        XCTAssertEqual(actual, vector["typedData"] as? NSDictionary)
        XCTAssertEqual(FundingHex.encode(EthereumAbi.encodeTyped(messageJson: json)), vector["digest"] as? String)
        // Public disposable key 1, never a user wallet or live funded account.
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let signature = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
        XCTAssertEqual(signature.hasPrefix("0x") ? signature : "0x" + signature, vector["signature"] as? String)
    }

    func testCalldataMatchesIndependentABICoderByteForByte() throws {
        let vector = try fixture()
        let plan = try makePlan()
        let signature = try XCTUnwrap(vector["signature"] as? String)
        let data = try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: signature, now: now)
        XCTAssertEqual(FundingHex.encode(data), vector["callData"] as? String)
        XCTAssertEqual(FundingHex.encode(plan.hookData), vector["hook"] as? String)
        XCTAssertEqual(data.count, 580)
        XCTAssertEqual(plan.hookData.count, 56)
        XCTAssertEqual(CCTPArbitrumRoute.destinationDex, 0)
    }

    func testAlteredAmountNonceOrWalletCannotReuseAuthorization() throws {
        let signature = try XCTUnwrap(try fixture()["signature"] as? String)
        let wrongWallet = DeviceWalletSummary(accountID: UUID(), address: wallet.address, recoveryVerified: true)
        XCTAssertThrowsError(try CCTPDepositCodec.callData(plan: makePlan(), wallet: wrongWallet,
            authorization: signature, now: now))
        for plan in [try makePlan(amount: "11"), try makePlan(nonce: Data(repeating: 18, count: 32))] {
            XCTAssertThrowsError(try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: signature, now: now))
        }
    }

    func testMalformedSignaturesAndHighSRejected() throws {
        let signature = try XCTUnwrap(try fixture()["signature"] as? String)
        let r = String(signature.dropFirst(2).prefix(64))
        let highS = "0x" + r + String(repeating: "f", count: 64) + "1b"
        for value in ["0x", signature + "00", String(signature.dropLast(2)) + "00", highS,
                      "0x" + String(repeating: "0", count: 128) + "1b", signature.uppercased()] {
            XCTAssertThrowsError(try CCTPDepositCodec.callData(plan: makePlan(), wallet: wallet, authorization: value, now: now))
        }
    }

    func testExpiredAndClockRollbackPlansCannotEncode() throws {
        let plan = try makePlan()
        for seconds in [-1.0, 60, 301] {
            XCTAssertThrowsError(try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet,
                now: now.addingTimeInterval(seconds)))
        }
    }

    func testInternalBackupIsOptionalButBadNonceAndAddressCannotCreatePlan() throws {
        let quote = try makePlan().quote
        for address in ["0x" + String(repeating: "0", count: 40), "not-an-address", wallet.address.uppercased()] {
            let wrong = DeviceWalletSummary(accountID: wallet.accountID, address: address, recoveryVerified: true)
            XCTAssertThrowsError(try CCTPDepositPlan(wallet: wrong, quote: quote, now: now))
        }
        let unverified = DeviceWalletSummary(accountID: wallet.accountID, address: wallet.address, recoveryVerified: false)
        XCTAssertNoThrow(try CCTPDepositPlan(wallet: unverified, quote: quote, now: now))
        XCTAssertFalse(unverified.recoveryVerified)
        XCTAssertThrowsError(try CCTPDepositPlan(wallet: wallet, quote: quote, now: now, nonce: Data(count: 31)))
        XCTAssertThrowsError(try CCTPDepositPlan(wallet: wallet, quote: quote, now: now.addingTimeInterval(60)))
    }

    func testOSRandomNonceAndFixedSelfRoute() throws {
        let quote = try makePlan().quote
        let first = try CCTPDepositPlan(wallet: wallet, quote: quote, now: now)
        let second = try CCTPDepositPlan(wallet: wallet, quote: quote, now: now)
        XCTAssertNotEqual(first.authorizationNonce, second.authorizationNonce)
        XCTAssertEqual(first.owner, wallet.address)
        XCTAssertEqual(first.validBefore - first.validAfter, 330)
        XCTAssertEqual(CCTPArbitrumRoute.extensionAddress, "0xa95d9c1f655341597c94393fddc30cf3c08e4fce")
        XCTAssertEqual(CCTPArbitrumRoute.forwarderAddress, "0xb21d281dedb17ae5b501f6aa8256fe38c4e45757")
    }

    private func makePlan(amount: String = "10", nonce: Data = Data(repeating: 17, count: 32)) throws -> CCTPDepositPlan {
        let schedule = try CCTPFeeSchedule.decode(Data(CCTPDepositQuoteTests.response.utf8), receivedAt: now)
        let quote = try CCTPDepositQuote(amount: amount, schedule: schedule, now: now)
        return try CCTPDepositPlan(wallet: wallet, quote: quote, now: now, nonce: nonce)
    }

    private func fixture() throws -> NSDictionary {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cctp-deposit-vector", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }
}
