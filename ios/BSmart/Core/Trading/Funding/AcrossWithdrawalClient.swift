import Foundation

enum AcrossWithdrawalError: String, Error, LocalizedError {
    case quoteUnavailable = "quote_unavailable"
    case quoteIncomplete = "quote_incomplete"
    case providerUnavailable = "provider_unavailable"
    case providerNotAuthorized = "provider_not_authorized"
    case unavailable = "withdrawal_unavailable"
    case disabled = "withdrawals_disabled"
    case pending = "withdrawal_pending"
    case quoteExpired = "quote_expired"
    case invalidInput = "invalid_input"
    case invalidSignature = "invalid_signature"
    case walletUnavailable = "wallet_unavailable"
    case upgradeRequired = "upgrade_required"

    var errorDescription: String? {
        switch self {
        case .quoteUnavailable:
            "Across could not quote this amount or route. Change the amount or try later.".bSmartLocalized
        case .quoteIncomplete:
            "Across returned an incomplete withdrawal quote. No transfer was made; please contact support."
                .bSmartLocalized
        case .providerUnavailable, .unavailable:
            "Across is temporarily unavailable. Refresh withdrawal status before trying again.".bSmartLocalized
        case .providerNotAuthorized:
            "Across withdrawals are not authorized for this app. Please contact support; no transfer was made.".bSmartLocalized
        case .disabled: "Withdrawals are not available yet.".bSmartLocalized
        case .pending: "A withdrawal is already pending. Refresh its status before trying again.".bSmartLocalized
        case .quoteExpired: "Withdrawal quote expired. Request a new quote.".bSmartLocalized
        case .invalidInput: "Check the Arbitrum address and USDC amount.".bSmartLocalized
        case .invalidSignature:
            "The withdrawal signature could not be verified. Request a new quote.".bSmartLocalized
        case .walletUnavailable: "This wallet is not ready for withdrawals.".bSmartLocalized
        case .upgradeRequired: "Please update the app to withdraw.".bSmartLocalized
        }
    }
}

struct AcrossWithdrawalRecord: Decodable, Identifiable, Sendable {
    let id: UUID
    let walletAddress: String
    let recipient: String
    let sourceDex: String
    let amountUnits: String
    let expectedOutputUnits: String
    let minOutputUnits: String
    let submissionFeeUnits: String?
    let submissionFeeDecimals: Int?
    let submissionFeeSymbol: String?
    let quoteExpiresAt: Date
    let depositId: String
    let state: String
    let providerStatus: String?
    let createdAt: Date

    var blocksNewWithdrawal: Bool {
        ["quoted", "submitting", "submitted", "uncertain", "deposit_pending", "expired"].contains(state)
    }

    var statusTitle: String {
        switch state {
        case "quoted": "Awaiting confirmation"
        case "submitting", "uncertain": "Checking submission"
        case "submitted", "deposit_pending": "Transfer in progress"
        case "expired": "Awaiting refund to HyperEVM"
        case "filled": "Received on Arbitrum"
        case "refunded": "Refunded on HyperEVM"
        case "deposit_failed": "Transfer failed; funds remain on HyperCore"
        default: "Withdrawal unavailable"
        }
    }

    static func formatted(_ units: String, decimals: Int) -> String? {
        guard (0...18).contains(decimals), let value = Decimal(string: units), value >= 0 else { return nil }
        let divisor = (0..<decimals).reduce(Decimal(1)) { value, _ in value * 10 }
        let result = value / divisor
        return NSDecimalNumber(decimal: result).stringValue
    }
}

struct AcrossWithdrawalQuote: Sendable {
    let record: AcrossWithdrawalRecord
    let steps: [AcrossSigningStep]
}

@MainActor
final class AcrossWithdrawalClient {
    private let account: AccountAccessStore
    private let transport: SupabaseAccountTransport
    private let base = "functions/v1/bsmart-withdrawals"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let raw = try value.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: value.codingPath,
                                                        debugDescription: "Invalid withdrawal timestamp"))
            }
            return date
        }
        return decoder
    }()

    init(account: AccountAccessStore) throws {
        guard let configuration = SupabaseAccountConfiguration.resolve() else { throw AccountAccessError.unavailable }
        self.account = account
        transport = SupabaseAccountTransport(configuration: configuration)
    }

    func history(wallet: DeviceWalletSummary) async throws -> [AcrossWithdrawalRecord] {
        let data = try await account.withFeedSession(expectedAccountID: wallet.accountID) { token in
            try await self.transport.request(self.base, token: token)
        }
        let items = try decoder.decode(History.self, from: data).withdrawals
        guard items.allSatisfy({ $0.walletAddress == wallet.address }) else { throw DeviceWalletError.accountChanged }
        return items
    }

    func quote(id: UUID, amount: String, source: String, recipient: String,
               wallet: DeviceWalletSummary) async throws -> AcrossWithdrawalQuote {
        let body = try JSONEncoder().encode(QuoteRequest(id: id.uuidString.lowercased(), walletAddress: wallet.address,
                                                          recipient: recipient, amount: amount, sourceDex: source))
        let data = try await account.withFeedSession(expectedAccountID: wallet.accountID) { token in
            try await self.transport.request("\(self.base)/quote", method: "POST", body: body, token: token,
                                             expectedStatus: 201)
        }
        let value = try decoder.decode(Item.self, from: data).withdrawal
        guard value.id == id, value.walletAddress == wallet.address, value.recipient == recipient,
              value.sourceDex == source, value.state == "quoted" else { throw AccountAccessError.invalidResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["swapTxns"] as? [[String: Any]], raw.count == 2 else {
            throw AccountAccessError.invalidResponse
        }
        let steps = raw.compactMap(AcrossSigningStep.init(json:))
        guard steps.count == 2, Set(steps.map(\.stepID)).count == 2,
              Set(steps.map(\.ecosystem)) == Set(["hypercore", "evm-gasless"]) else {
            throw AccountAccessError.invalidResponse
        }
        return .init(record: value, steps: steps)
    }

    func submit(_ quote: AcrossWithdrawalQuote, signatures: [String: String],
                wallet: DeviceWalletSummary) async throws -> AcrossWithdrawalRecord {
        let body = try JSONEncoder().encode(Signatures(signaturesByStepId: signatures))
        let id = quote.record.id.uuidString.lowercased()
        let data = try await account.withFeedSession(expectedAccountID: wallet.accountID) { token in
            try await self.transport.request("\(self.base)/\(id)/submit", method: "POST", body: body, token: token)
        }
        let item = try decoder.decode(Item.self, from: data).withdrawal
        guard item.id == quote.record.id, item.walletAddress == wallet.address,
              ["submitted", "uncertain", "deposit_pending", "filled"].contains(item.state) else {
            throw AccountAccessError.invalidResponse
        }
        return item
    }

    func cancel(_ quote: AcrossWithdrawalQuote, wallet: DeviceWalletSummary) async throws {
        let id = quote.record.id.uuidString.lowercased()
        let data = try await account.withFeedSession(expectedAccountID: wallet.accountID) { token in
            try await self.transport.request("\(self.base)/\(id)/cancel", method: "POST", token: token)
        }
        let item = try decoder.decode(Item.self, from: data).withdrawal
        guard item.id == quote.record.id, item.state == "cancelled" else { throw AccountAccessError.invalidResponse }
    }

    private struct History: Decodable { let withdrawals: [AcrossWithdrawalRecord] }
    private struct Item: Decodable { let withdrawal: AcrossWithdrawalRecord }
    private struct QuoteRequest: Encodable {
        let id: String
        let walletAddress: String
        let recipient: String
        let amount: String
        let sourceDex: String
    }
    private struct Signatures: Encodable { let signaturesByStepId: [String: String] }
}
