import Foundation

@MainActor
protocol ManagedFundingServicing {
    var accountID: UUID? { get }
    func available(wallet: DeviceWalletSummary) async throws -> Bool
    func address(wallet: DeviceWalletSummary, network: ManagedFundingNetwork) async throws -> ManagedFundingAddress
    func deposits(wallet: DeviceWalletSummary) async throws -> [ManagedFundingDeposit]
}

@MainActor
final class ManagedFundingClient: ManagedFundingServicing {
    private let account: AccountAccessStore
    private let transport: SupabaseAccountTransport?
    var accountID: UUID? { account.walletAccountID }

    init(account: AccountAccessStore) {
        self.account = account
        transport = SupabaseAccountConfiguration.resolve().map { SupabaseAccountTransport(configuration: $0) }
    }

    private func request(_ path: String, wallet: DeviceWalletSummary, body: Data? = nil) async throws -> Data {
        guard let transport, accountID == wallet.accountID else { throw ManagedFundingError.unavailable }
        let revision = account.walletSessionRevision
        let token = try await account.embeddedWalletAccessToken(expectedAccountID: wallet.accountID)
        let data = try await transport.request("functions/v1/bsmart-funding" + path,
            method: body == nil ? "GET" : "POST", body: body, token: token)
        try Task.checkCancellation()
        guard accountID == wallet.accountID, revision == account.walletSessionRevision else {
            throw DeviceWalletError.accountChanged
        }
        return data
    }

    func available(wallet: DeviceWalletSummary) async throws -> Bool {
        struct Status: Decodable { let available: Bool }
        return try JSONDecoder().decode(Status.self, from: await request("", wallet: wallet)).available
    }

    func address(wallet: DeviceWalletSummary, network: ManagedFundingNetwork) async throws -> ManagedFundingAddress {
        let body = try JSONSerialization.data(withJSONObject: ["network": network.rawValue])
        let result = try BSmartJSONCoding.makeDecoder().decode(ManagedFundingAddress.self,
            from: await request("/address", wallet: wallet, body: body))
        try result.validate(owner: wallet.address, network: network)
        return result
    }

    func deposits(wallet: DeviceWalletSummary) async throws -> [ManagedFundingDeposit] {
        struct History: Decodable { let recipient: String; let deposits: [ManagedFundingDeposit] }
        let result = try BSmartJSONCoding.makeDecoder().decode(History.self,
            from: await request("/deposits", wallet: wallet))
        guard result.recipient == wallet.address, result.deposits.count <= 20,
              Set(result.deposits.map(\.id)).count == result.deposits.count else { throw ManagedFundingError.unavailable }
        return result.deposits
    }
}
