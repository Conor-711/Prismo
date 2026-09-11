import XCTest
import Security
import SQLite3
import WalletCore
@testable import BSmart

struct FundingJournalTestContext: Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("funding-journal-" + UUID().uuidString)
    let keychain = JournalTestKeychain()
    let clock = JournalTestClock()
    let service = "journal-test-" + UUID().uuidString
    let wallet = PreflightTestFixture.wallet
    var database: URL { directory.appendingPathComponent("transactions.sqlite") }

    func journal(probe: @escaping @Sendable (FundingJournalCommitPhase) throws -> Void = { _ in }) throws -> FundingTransactionJournal {
        try .init(directory: directory, service: service, keychain: keychain, clock: { clock.now }, commitProbe: probe)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    func transaction(nonce: String = "0x0", authorizationNonce: UInt8 = 17) async throws -> CCTPSourceTransaction {
        let now = clock.now
        let authNonce = Data(repeating: authorizationNonce, count: 32)
        let schedule = try CCTPFeeSchedule.decode(Data(CCTPDepositQuoteTests.response.utf8), receivedAt: now)
        let plan = try CCTPDepositPlan(wallet: wallet, quote: CCTPDepositQuote(amount: "10", schedule: schedule, now: now),
                                       now: now, nonce: authNonce)
        let json = try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet, now: now)
        let text = try EthereumMessageSigner.signTypedMessage(privateKey: Self.publicTestKey(), messageJson: json)
        let signature = text.hasPrefix("0x") ? text : "0x" + text
        let rpc = try PreflightStubRPC(overrides: ["nonce": .string(nonce), "pendingNonce": .string(nonce)],
                                       blockTime: now, authorizationNonce: authNonce)
        let preflight = try await ArbitrumSourcePreflight(rpc: rpc, clock: { now }).prepare(plan: plan, wallet: wallet, authorization: signature)
        return try .init(preflight: preflight, wallet: wallet, now: now)
    }

    func signed(_ transaction: CCTPSourceTransaction) throws -> CCTPSignedSourceTransaction {
        let signature = try XCTUnwrap(Self.publicTestKey().sign(digest: transaction.signingHash, curve: .secp256k1))
        return try transaction.compile(signature: signature, wallet: wallet, now: clock.now)
    }

    // Reconstruct the check observed at signing time; expiry tests intentionally pass it after its deadline.
    func recordedSubmissionCheck(_ signed: CCTPSignedSourceTransaction) async throws -> FundingSubmissionCheck {
        let source = signed.transaction.preflight
        let rpc = try PreflightStubRPC(overrides: ["nonce": .string(source.nonce.rpc), "pendingNonce": .string(source.nonce.rpc)],
            blockTime: source.checkedAt, authorizationNonce: source.plan.authorizationNonce)
        return try await ArbitrumSourceSubmissionCheck(rpc: rpc, clock: { source.checkedAt }).check(signed: signed, wallet: wallet)
    }

    func ready(_ transaction: CCTPSourceTransaction, id: UUID, journal: FundingTransactionJournal) async throws -> CCTPSignedSourceTransaction {
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: wallet)
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: wallet)
        let signed = try signed(transaction)
        _ = try await journal.acceptSignature(id: id, signed: signed, wallet: wallet)
        return signed
    }

    func readyWithConsent(_ transaction: CCTPSourceTransaction, id: UUID, journal: FundingTransactionJournal) async throws -> CCTPSignedSourceTransaction {
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: wallet)
        _ = try await journal.beginAuthorization(id: id, wallet: wallet)
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: wallet)
        return try await ready(transaction, id: id, journal: journal)
    }

    func mutateDatabase(_ sql: String) throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, sql, nil, nil, nil), SQLITE_OK)
    }

    private static func publicTestKey() throws -> PrivateKey {
        // Public disposable vector, never a system/device wallet key.
        try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
    }
}

final class JournalTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = PreflightTestFixture.now
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value += seconds }
}

final class JournalTestKeychain: WalletKeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private var readsLocked = false
    private var failAtUpdate: Int?
    private var updates = 0
    private var attributes: [String: Any] = [:]
    var data: Data? { lock.lock(); defer { lock.unlock() }; return bytes }
    var addAttributes: [String: Any] { lock.lock(); defer { lock.unlock() }; return attributes }

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.lock(); defer { lock.unlock() }
        if readsLocked { return (errSecInteractionNotAllowed, nil) }
        return bytes.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard bytes == nil else { return errSecDuplicateItem }
        self.attributes = attributes
        bytes = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        updates += 1
        if failAtUpdate == updates { return errSecNotAvailable }
        bytes = values[kSecValueData as String] as? Data
        return errSecSuccess
    }
    func forget() { lock.lock(); defer { lock.unlock() }; bytes = nil }
    func setLocked() { lock.lock(); defer { lock.unlock() }; readsLocked = true }
    func failFinalization() { lock.lock(); defer { lock.unlock() }; failAtUpdate = updates + 2 }
}

func expectJournalFailure<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await operation(); XCTFail("Expected journal operation to fail closed", file: file, line: line) }
    catch { }
}
