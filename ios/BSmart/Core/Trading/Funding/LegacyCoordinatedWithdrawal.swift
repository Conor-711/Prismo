import Foundation

// Kept only to read existing local withdrawal journal entries.
struct CoordinatedWithdrawal: Decodable, Identifiable, Sendable {
    enum State: String, Decodable, Sendable {
        case reserved, submitting, accepted, uncertain, coreDebited = "core_debited"
        case rejected, cancelled, expired

        var blocksNewWithdrawal: Bool {
            [.reserved, .submitting, .uncertain].contains(self)
        }
    }

    let id: UUID
    let walletAddress: String
    let recipient: String
    let amount: String
    let sourceDex: String
    let nonce: String
    let state: State
    let ledgerHash: String?
    let ledgerTime: Int64?
    let createdAt: String
    let expiresAt: String
    let exchangeResponseBase64: String?

    var exchangeResponse: Data? { exchangeResponseBase64.flatMap { Data(base64Encoded: $0) } }

    func matches(_ intent: HyperliquidArchivedWithdrawal) -> Bool {
        walletAddress == intent.owner && recipient == intent.recipient && amount == intent.amount &&
            sourceDex == intent.source && nonce == String(intent.nonce)
    }
}
