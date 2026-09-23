import Foundation

@MainActor
protocol EmbeddedWalletInventory {
    var addresses: [String] { get }
    func refresh() async throws
    func create() async throws -> String
}

enum EmbeddedWalletLookup {
    @MainActor
    static func resolve(_ inventory: any EmbeddedWalletInventory, registeredAddress: String?,
                        create: Bool, reconcileCreation: Bool) async throws -> String? {
        // Login already supplies the wallet list. Refresh only to reconcile missing state.
        if reconcileCreation || registeredAddress.map({ expected in
            !inventory.addresses.contains { $0.lowercased() == expected }
        }) == true {
            try await inventory.refresh()
        }
        let addresses = inventory.addresses.map { $0.lowercased() }
        if let expected = registeredAddress { return addresses.first { $0 == expected } }
        guard addresses.count <= 1 else { throw EmbeddedWalletError.walletMismatch }
        if let existing = addresses.first { return existing }
        guard create else { return nil }
        return try await inventory.create().lowercased()
    }
}

struct EmbeddedWalletBackoff {
    private var failures = 0
    private var retryAt: ContinuousClock.Instant?

    func remaining(at now: ContinuousClock.Instant = .now) -> Int {
        guard let retryAt, retryAt > now else { return 0 }
        let duration = now.duration(to: retryAt).components
        return Int(duration.seconds) + (duration.attoseconds > 0 ? 1 : 0)
    }

    mutating func limited(at now: ContinuousClock.Instant = .now) -> Int {
        failures = min(failures + 1, 4)
        let seconds = min(60 * (1 << (failures - 1)), 300)
        retryAt = now.advanced(by: .seconds(seconds))
        return seconds
    }

    mutating func succeeded() { failures = 0; retryAt = nil }
}
