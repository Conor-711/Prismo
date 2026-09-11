import XCTest
import WalletCore
@testable import BSmart

final class CCTPSourceTransactionTests: XCTestCase {
    private let wallet = PreflightTestFixture.wallet
    private let now = PreflightTestFixture.now

    func testTypeTwoMatchesIndependentSigningHashRawBytesAndTransactionHash() async throws {
        for vector in try vectors() {
            let preflight = try await prepared(vector)
            let transaction = try CCTPSourceTransaction(preflight: preflight, wallet: wallet, now: now)
            XCTAssertEqual(FundingHex.encode(transaction.signingHash), vector.signingHash)
            XCTAssertEqual(preflight.gasLimit.rpc, vector.gasLimit)
            XCTAssertEqual(preflight.maximumFeePerGas.rpc, vector.maximumFeePerGas)
            XCTAssertEqual(preflight.maximumNetworkFee.rpc, vector.maximumNetworkFee)
            let signed = try transaction.compile(signature: XCTUnwrap(FundingHex.decode(vector.signature)), wallet: wallet, now: now)
            XCTAssertEqual(FundingHex.encode(signed.raw), vector.rawTransaction)
            XCTAssertEqual(signed.hash, vector.transactionHash)
            XCTAssertEqual(signed.raw.first, 2)
            XCTAssertEqual(signed.transaction.preflight.plan.owner, vector.owner)
        }
    }

    func testOfflineWalletCoreKeyProducesTheIndependentSignature() async throws {
        // This is public disposable key 1, not a device wallet or a live signing path.
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        for vector in try vectors() {
            let transaction = try CCTPSourceTransaction(preflight: await prepared(vector), wallet: wallet, now: now)
            let signature = try XCTUnwrap(key.sign(digest: transaction.signingHash, curve: .secp256k1))
            XCTAssertEqual(FundingHex.encode(signature), vector.signature)
            XCTAssertEqual(try transaction.compile(signature: signature, wallet: wallet, now: now).hash, vector.transactionHash)
        }
    }

    func testEveryCalldataByteIsBoundIncludingSelectorHookAndPadding() async throws {
        let result = try await prepared(vectors()[0])
        for index in result.callData.indices {
            var changed = result.callData
            changed[index] ^= 1
            XCTAssertThrowsError(try CCTPSourceTransaction(preflight: copy(result, data: changed), wallet: wallet, now: now))
        }
        for data in [Data(), Data(result.callData.dropLast()), result.callData + Data([0])] {
            XCTAssertThrowsError(try CCTPSourceTransaction(preflight: copy(result, data: data), wallet: wallet, now: now))
        }
    }

    func testPreflightNonceGasFeeAndAuthorizationCannotBeReplaced() async throws {
        let result = try await prepared(vectors()[0])
        let variants = [
            copy(result, authorization: "0x"),
            copy(result, nonce: FundingQuantity(1)),
            copy(result, estimatedGas: FundingQuantity(199_999)),
            copy(result, gasLimit: FundingQuantity(240_001)),
            copy(result, gasPrice: FundingQuantity(10_000_001)),
            copy(result, maximumFeePerGas: FundingQuantity(20_000_001)),
            copy(result, maximumNetworkFee: FundingQuantity(0)),
            copy(result, checkedAt: now.addingTimeInterval(-1))
        ]
        for changed in variants {
            XCTAssertThrowsError(try CCTPSourceTransaction(preflight: changed, wallet: wallet, now: now))
        }
    }

    func testAnotherValidEnvelopeCannotReuseOldSignature() async throws {
        let fixtures = try vectors()
        let signature = try XCTUnwrap(FundingHex.decode(fixtures[0].signature))
        for vector in fixtures.dropFirst() {
            let transaction = try CCTPSourceTransaction(preflight: await prepared(vector), wallet: wallet, now: now)
            XCTAssertThrowsError(try transaction.compile(signature: signature, wallet: wallet, now: now))
        }
    }

    func testWrongSignerAndWrongSigningSchemeRejected() async throws {
        let vector = try vectors()[0]
        let transaction = try CCTPSourceTransaction(preflight: await prepared(vector), wallet: wallet, now: now)
        let wrongKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([2])))
        let wrongSignature = try XCTUnwrap(wrongKey.sign(digest: transaction.signingHash, curve: .secp256k1))
        XCTAssertThrowsError(try transaction.compile(signature: wrongSignature, wallet: wallet, now: now))
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
        let personal = EthereumMessageSigner.signMessage(privateKey: key, message: FundingHex.encode(transaction.signingHash))
        var personalBytes = try XCTUnwrap(FundingHex.decode(personal.hasPrefix("0x") ? personal : "0x" + personal))
        personalBytes[64] -= 27
        XCTAssertThrowsError(try transaction.compile(signature: personalBytes, wallet: wallet, now: now))
        var authorization = try XCTUnwrap(FundingHex.decode(PreflightTestFixture.signature()))
        authorization[64] -= 27
        XCTAssertThrowsError(try transaction.compile(signature: authorization, wallet: wallet, now: now))
    }

    func testMalformedMalleableAndLegacySignaturesRejected() async throws {
        let vector = try vectors()[0]
        let transaction = try CCTPSourceTransaction(preflight: await prepared(vector), wallet: wallet, now: now)
        let valid = try XCTUnwrap(FundingHex.decode(vector.signature))
        let order = try XCTUnwrap(FundingHex.decode("0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"))
        var variants = [Data(), Data(valid.dropLast()), valid + Data([0])]
        for parity: UInt8 in [2, 27, 28, 37, 255] { variants.append(Data(valid.prefix(64)) + Data([parity])) }
        variants += [Data(count: 32) + valid.dropFirst(32), order + valid.dropFirst(32),
                     valid.prefix(32) + Data(count: 32) + valid.suffix(1),
                     valid.prefix(32) + Data(repeating: 255, count: 32) + valid.suffix(1)]
        for bytes in variants {
            XCTAssertThrowsError(try transaction.compile(signature: bytes, wallet: wallet, now: now))
        }
    }

    func testExpiryAndClockRollbackBlockBothPreparationAndCompilation() async throws {
        let vector = try vectors()[0]
        let preflight = try await prepared(vector)
        let transaction = try CCTPSourceTransaction(preflight: preflight, wallet: wallet, now: now)
        let signature = try XCTUnwrap(FundingHex.decode(vector.signature))
        for seconds in [-1.0, 30, 60, 301] {
            let time = now.addingTimeInterval(seconds)
            XCTAssertThrowsError(try CCTPSourceTransaction(preflight: preflight, wallet: wallet, now: time))
            XCTAssertThrowsError(try transaction.compile(signature: signature, wallet: wallet, now: time))
        }
    }

    func testAccountAndAddressChangesBlockCompilationButInternalBackupIsOptional() async throws {
        let vector = try vectors()[0]
        let preflight = try await prepared(vector)
        let transaction = try CCTPSourceTransaction(preflight: preflight, wallet: wallet, now: now)
        let signature = try XCTUnwrap(FundingHex.decode(vector.signature))
        for changed in [
            DeviceWalletSummary(accountID: UUID(), address: wallet.address, recoveryVerified: true),
            DeviceWalletSummary(accountID: wallet.accountID, address: "0x" + String(repeating: "1", count: 40), recoveryVerified: true)
        ] {
            XCTAssertThrowsError(try CCTPSourceTransaction(preflight: preflight, wallet: changed, now: now))
            XCTAssertThrowsError(try transaction.compile(signature: signature, wallet: changed, now: now))
        }
        let unbacked = DeviceWalletSummary(accountID: wallet.accountID, address: wallet.address, recoveryVerified: false)
        XCTAssertNoThrow(try CCTPSourceTransaction(preflight: preflight, wallet: unbacked, now: now))
        XCTAssertNoThrow(try transaction.compile(signature: signature, wallet: unbacked, now: now))
    }

    func testCompiledBytesAndHashRemainStableWithoutAnyRPCSubmission() async throws {
        let vector = try vectors()[0]
        let transaction = try CCTPSourceTransaction(preflight: await prepared(vector), wallet: wallet, now: now)
        let signature = try XCTUnwrap(FundingHex.decode(vector.signature))
        let first = try transaction.compile(signature: signature, wallet: wallet, now: now)
        let second = try transaction.compile(signature: signature, wallet: wallet, now: now.addingTimeInterval(1))
        XCTAssertEqual(first.raw, second.raw)
        XCTAssertEqual(first.hash, second.hash)
        var externalCopy = first.raw
        externalCopy[0] = 1
        XCTAssertEqual(first.raw.first, 2)
        XCTAssertEqual(first.hash, vector.transactionHash)
    }

    private func prepared(_ vector: SourceVector) async throws -> CCTPSourcePreflight {
        let rpc = try PreflightStubRPC(overrides: ["nonce": .string(vector.nonce), "pendingNonce": .string(vector.nonce),
            "gas": .string(vector.estimatedGas), "gasPrice": .string(vector.gasPrice)])
        return try await ArbitrumSourcePreflight(rpc: rpc, clock: { PreflightTestFixture.now })
            .prepare(plan: PreflightTestFixture.plan(), wallet: wallet, authorization: PreflightTestFixture.signature())
    }

    private func vectors() throws -> [SourceVector] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cctp-source-transaction-vectors", withExtension: "json"))
        return try JSONDecoder().decode([SourceVector].self, from: Data(contentsOf: url))
    }

    private func copy(_ value: CCTPSourcePreflight, authorization: String? = nil, data: Data? = nil, nonce: FundingQuantity? = nil,
                      estimatedGas: FundingQuantity? = nil, gasLimit: FundingQuantity? = nil, gasPrice: FundingQuantity? = nil,
                      maximumFeePerGas: FundingQuantity? = nil, maximumNetworkFee: FundingQuantity? = nil,
                      checkedAt: Date? = nil) -> CCTPSourcePreflight {
        .init(plan: value.plan, source: value.source, authorization: authorization ?? value.authorization,
              callData: data ?? value.callData, nonce: nonce ?? value.nonce, estimatedGas: estimatedGas ?? value.estimatedGas,
              gasLimit: gasLimit ?? value.gasLimit, gasPrice: gasPrice ?? value.gasPrice,
              maximumFeePerGas: maximumFeePerGas ?? value.maximumFeePerGas,
              maximumNetworkFee: maximumNetworkFee ?? value.maximumNetworkFee, checkedAt: checkedAt ?? value.checkedAt)
    }
}

private struct SourceVector: Decodable {
    let owner, nonce, estimatedGas, gasPrice, gasLimit, maximumFeePerGas, maximumNetworkFee: String
    let signingHash, signature, rawTransaction, transactionHash: String
}
