import Foundation
import Combine

@MainActor
final class CCTPTransferStore: ObservableObject {
    @Published private(set) var isQuoting = false
    @Published private(set) var quoteError: String?
    let preparation: CCTPDepositPreparation
    private let fees: CCTPFeeProviding
    private let isEnabled: () -> Bool
    private let clock: @Sendable () -> Date
    private var revision = UUID()
    private var subscription: AnyCancellable?

    init(preparation: CCTPDepositPreparation, fees: CCTPFeeProviding = CCTPFeeClient(),
         clock: @escaping @Sendable () -> Date = { Date() }, isEnabled: @escaping () -> Bool) {
        self.preparation = preparation; self.fees = fees; self.clock = clock; self.isEnabled = isEnabled
        subscription = preparation.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isBusy: Bool { isQuoting || preparation.isBusy }
    var errorMessage: String? { quoteError ?? preparation.errorMessage }
    var display: CCTPTransferDisplay { .init(preparation.state) }

    func review(amount: String, wallet: DeviceWalletSummary) async {
        guard isEnabled(), !isBusy, case .idle = preparation.state else { return }
        let operation = revision
        isQuoting = true; quoteError = nil
        defer { if operation == revision { isQuoting = false } }
        do {
            try Task.checkCancellation()
            _ = try ArbitrumDepositPolicy.validate(amount: amount, chainID: ArbitrumDepositPolicy.chainID,
                                                   tokenAddress: ArbitrumDepositPolicy.nativeUSDC)
            let schedule = try await fees.schedule()
            try Task.checkCancellation()
            guard operation == revision, isEnabled() else { return }
            let quote = try CCTPDepositQuote(amount: amount, schedule: schedule, now: clock())
            let plan = try CCTPDepositPlan(wallet: wallet, quote: quote, now: clock())
            await preparation.review(plan: plan, wallet: wallet)
        } catch {
            guard operation == revision, !Task.isCancelled else { return }
            if error is ArbitrumDepositPolicy.ValidationError { quoteError = CCTPFundingError.invalidAmount.errorDescription }
            else { quoteError = (error as? CCTPFundingError ?? .unavailable).errorDescription }
        }
    }

    func authorize() async {
        guard isEnabled(), !isBusy else { return }
        await preparation.authorize()
    }

    func sign() async {
        guard isEnabled(), !isBusy else { return }
        await preparation.signConfirmedTransaction()
    }

    func submit() async {
        guard isEnabled(), !isBusy else { return }
        await preparation.submitConfirmedTransaction()
    }

    func cancelReview() async {
        guard !isBusy else { return }
        await preparation.cancelUnsignedReview()
    }

    func invalidate() {
        revision = UUID(); isQuoting = false; quoteError = nil
        preparation.invalidate()
    }
}
