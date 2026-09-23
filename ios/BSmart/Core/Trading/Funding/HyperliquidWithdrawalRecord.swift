import Foundation

struct HyperliquidArchivedWithdrawal: Codable, Equatable, Sendable {
    let accountID: UUID
    let owner: String
    let recipient: String
    let amount: String
    let source: String
    let nonce: UInt64

    init(_ intent: HyperliquidWithdrawalIntent) {
        accountID = intent.accountID; owner = intent.owner; recipient = intent.recipient
        amount = intent.amount.wire; source = intent.source.rawValue; nonce = intent.nonce
    }

    var wallet: DeviceWalletSummary { .init(accountID: accountID, address: owner, recoveryVerified: true) }

    func restored(wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalIntent {
        guard wallet.accountID == accountID, wallet.address == owner,
              let source = HyperliquidWithdrawalIntent.Source(rawValue: source) else { throw FundingJournalError.conflict }
        let intent = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: recipient, amount: amount, source: source, nonce: nonce)
        guard intent.recipient == recipient, intent.amount.wire == amount else { throw FundingJournalError.integrity }
        return intent
    }
}

enum HyperliquidWithdrawalAcknowledgement: Equatable, Sendable {
    case accepted
    case rejected(String)

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 8192,
              case .object(let fields) = try JSONDecoder().decode(FundingRPCValue.self, from: data),
              Set(fields.keys) == ["status", "response"] else { throw HyperliquidWithdrawalError.invalidResponse }
        switch (fields["status"], fields["response"]) {
        case (.string("ok"), .object(let response)) where response == ["type": .string("default")]: return .accepted
        case (.string("err"), .string(let reason)):
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.utf8.count <= 2048,
                  !reason.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw HyperliquidWithdrawalError.invalidResponse
            }
            return .rejected(reason)
        default: throw HyperliquidWithdrawalError.invalidResponse
        }
    }
}

// Durable evidence only. Neither a record nor an API acceptance proves funds arrived.
struct HyperliquidWithdrawalRecord: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable {
        case review, signing, signed, submitting, accepted, uncertain, coreDebited, rejected, cancelled, abandoned
    }
    let id: UUID
    let intent: HyperliquidArchivedWithdrawal
    let createdAt: Date
    let reviewExpiresAt: Date
    var state: State
    var signature: String?
    var response: Data?
    var updatedAt: Date

    var acknowledgement: HyperliquidWithdrawalAcknowledgement? {
        response.flatMap { try? HyperliquidWithdrawalAcknowledgement.decode($0) }
    }

    func blocksNewAction(at now: Date) -> Bool {
        switch state {
        case .review: return now < reviewExpiresAt
        case .signing, .signed, .submitting, .uncertain: return true
        // Acceptance debits HyperCore, not proof of destination arrival. A new explicit
        // withdrawal may use a fresh balance; this record can never be submitted again.
        case .accepted, .coreDebited, .rejected, .cancelled, .abandoned: return false
        }
    }

    func validate(after previous: Self?) throws {
        let restored = try intent.restored(wallet: intent.wallet)
        guard [createdAt, reviewExpiresAt, updatedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              createdAt.timeIntervalSince1970 > 0, updatedAt >= createdAt,
              reviewExpiresAt > createdAt, reviewExpiresAt.timeIntervalSince(createdAt) <= 60,
              abs(Double(intent.nonce) - createdAt.timeIntervalSince1970 * 1000) <= 1000 else {
            throw FundingJournalError.integrity
        }
        if let signature { _ = try HyperliquidWithdrawalCodec.envelope(restored, signature: signature) }
        switch state {
        case .review, .signing, .cancelled:
            guard signature == nil, response == nil else { throw FundingJournalError.integrity }
        case .signed, .submitting, .uncertain:
            guard signature != nil, response == nil else { throw FundingJournalError.integrity }
        case .abandoned:
            guard response == nil else { throw FundingJournalError.integrity }
        case .coreDebited:
            guard signature != nil else { throw FundingJournalError.integrity }
        case .accepted:
            guard signature != nil, acknowledgement == .accepted else { throw FundingJournalError.integrity }
        case .rejected:
            guard signature != nil, case .rejected = acknowledgement else { throw FundingJournalError.integrity }
        }
        guard let previous else {
            guard state == .review, updatedAt == createdAt else { throw FundingJournalError.invalidTransition }
            return
        }
        guard id == previous.id, intent == previous.intent, createdAt == previous.createdAt,
              reviewExpiresAt == previous.reviewExpiresAt, updatedAt >= previous.updatedAt,
              previous.signature == nil || previous.signature == signature else { throw FundingJournalError.conflict }
        let allowed: [State]
        switch previous.state {
        case .review: allowed = [.signing, .cancelled, .abandoned]
        case .signing: allowed = [.signed, .abandoned]
        case .signed: allowed = [.submitting, .abandoned]
        case .submitting: allowed = [.accepted, .rejected, .uncertain, .coreDebited, .abandoned]
        case .accepted: allowed = [.coreDebited]
        case .uncertain: allowed = [.accepted, .rejected, .coreDebited, .abandoned]
        case .coreDebited, .rejected, .cancelled, .abandoned: allowed = []
        }
        guard allowed.contains(state), state != .signing || updatedAt < reviewExpiresAt else {
            throw FundingJournalError.invalidTransition
        }
    }
}
