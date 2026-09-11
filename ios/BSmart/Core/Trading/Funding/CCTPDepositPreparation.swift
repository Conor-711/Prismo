import Foundation
import Combine

enum CCTPDepositPreparationState {
    case idle
    case checkingAccount
    case reviewAuthorization(FundingConsentRecord)
    case authorizing
    case preflighting
    case reviewNetworkFee(CCTPSourceTransaction)
    case signing
    case signatureRecorded(FundingJournalRecord)
    case checkingSubmission
    case submitting
    case submissionRecorded(FundingHistoryEntry)
    case recoveryRequired
}

// Explicit confirmation orchestration. No receiving address, spendable balance or automatic signing/retry.
@MainActor
final class CCTPDepositPreparation: ObservableObject {
    @Published private(set) var state = CCTPDepositPreparationState.idle
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    private let service: AccountWalletServicing
    private let signer: FundingDeviceSigning
    private let preflight: CCTPSourcePreparing
    private let journal: FundingTransactionJournal
    private let submissionCheck: CCTPSourceSubmissionChecking
    private let broadcaster: ArbitrumFundingBroadcasting
    private let clock: @Sendable () -> Date
    private let isEnabled: () -> Bool
    private var lease: FundingSigningLease?
    private var intentID: UUID?
    private var signedSource: CCTPSignedSourceTransaction?
    private var revision = UUID()

    init(service: AccountWalletServicing, signer: FundingDeviceSigning, journal: FundingTransactionJournal,
         preflight: CCTPSourcePreparing = ArbitrumSourcePreflight(),
         submissionCheck: CCTPSourceSubmissionChecking = ArbitrumSourceSubmissionCheck(),
         broadcaster: ArbitrumFundingBroadcasting = ArbitrumFundingBroadcaster(),
         clock: @escaping @Sendable () -> Date = { Date() }, isEnabled: @escaping () -> Bool = { false }) {
        self.service = service
        self.signer = signer
        self.journal = journal
        self.preflight = preflight
        self.submissionCheck = submissionCheck
        self.broadcaster = broadcaster
        self.clock = clock
        self.isEnabled = isEnabled
    }

    // The owning screen must call on background, departure, account/session change or explicit cancellation.
    func invalidate() {
        lease?.invalidate()
        lease = nil
        signedSource = nil
        revision = UUID()
        state = intentID == nil ? .idle : .recoveryRequired
        errorMessage = nil
    }

    func review(plan: CCTPDepositPlan, wallet: DeviceWalletSummary) async {
        guard !isBusy else { return }
        if case .idle = state { } else { return }
        let operation = revision
        isBusy = true
        errorMessage = nil
        state = .checkingAccount
        defer { isBusy = false }
        do {
            try await verifyRegistration(wallet: wallet, operation: operation)
            try await verifySource(plan: plan, wallet: wallet, operation: operation)
            let id = UUID()
            intentID = id
            let consent = try await journal.beginConsent(id: id, plan: plan, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            lease = try service.fundingSigningLease(wallet: wallet)
            state = .reviewAuthorization(consent)
        } catch { fail(error, operation: operation) }
    }

    func authorize() async {
        guard !isBusy, case .reviewAuthorization(let consent) = state, let lease,
              intentID == consent.id else { return }
        let operation = revision
        let wallet = lease.wallet
        isBusy = true
        errorMessage = nil
        state = .authorizing
        defer { isBusy = false }
        do {
            try await verifyRegistration(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            try await verifySource(plan: consent.plan.restored(), wallet: wallet, operation: operation)
            let permit = try await journal.beginAuthorization(id: consent.id, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            let authorization = try await signer.authorizeDeposit(permit, lease: lease)
            // Capture the side effect before cancellation, account checks or another network request.
            _ = try await journal.recordAuthorization(id: consent.id, signature: authorization, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            state = .preflighting
            let checked = try await preflight.prepare(plan: permit.plan, wallet: wallet, authorization: authorization)
            try check(wallet: wallet, operation: operation)
            let transaction = try CCTPSourceTransaction(preflight: checked, wallet: wallet, now: clock())
            _ = try await journal.reserve(id: consent.id, transaction: transaction, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            state = .reviewNetworkFee(transaction)
        } catch { fail(error, operation: operation) }
    }

    func signConfirmedTransaction() async {
        guard !isBusy, case .reviewNetworkFee(let transaction) = state, let lease, let id = intentID else { return }
        let operation = revision
        let wallet = lease.wallet
        isBusy = true
        errorMessage = nil
        state = .signing
        defer { isBusy = false }
        do {
            try await verifyRegistration(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            let permit = try await journal.beginSigning(id: id, transaction: transaction, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            let signature = try await signer.signDeposit(permit, transaction: transaction, lease: lease)
            let recorded = try await journal.recordSignature(id: id, signature: signature, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            signedSource = try transaction.compile(signature: signature, wallet: wallet, now: clock())
            state = .signatureRecorded(recorded)
        } catch { fail(error, operation: operation) }
    }

    func submitConfirmedTransaction() async {
        guard !isBusy, case .signatureRecorded = state, let signed = signedSource,
              let lease, let id = intentID else { return }
        let wallet = lease.wallet
        let operation = revision
        isBusy = true
        errorMessage = nil
        state = .checkingSubmission
        defer { isBusy = false; signedSource = nil }
        do {
            try await verifyRegistration(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            let checked = try await submissionCheck.check(signed: signed, wallet: wallet)
            try check(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            let permit = try await journal.beginSubmission(id: id, signed: signed, wallet: wallet, check: checked)
            let result: FundingSubmissionOutcome
            do {
                try check(wallet: wallet, operation: operation)
                state = .submitting
                result = try await broadcaster.submit(permit, lease: lease)
            } catch {
                // Once permission was persisted, no exception may reset the deposit to retryable.
                result = .uncertain
            }
            let record = try await journal.recordSubmissionResult(id: id, wallet: wallet, reportedHash: result.reportedHash)
            try check(wallet: wallet, operation: operation)
            try lease.check(wallet: wallet)
            state = .submissionRecorded(try FundingHistoryEntry(source: record))
            lease.invalidate()
            self.lease = nil
        } catch { fail(error, operation: operation) }
    }

    func cancelUnsignedReview() async {
        guard !isBusy, let lease, let id = intentID else { return }
        let hasSource: Bool
        switch state {
        case .reviewAuthorization: hasSource = false
        case .reviewNetworkFee: hasSource = true
        default: return
        }
        let operation = revision
        isBusy = true
        defer { isBusy = false }
        do {
            try check(wallet: lease.wallet, operation: operation)
            if hasSource { _ = try await journal.cancelPrepared(id: id, wallet: lease.wallet) }
            else { _ = try await journal.cancelConsent(id: id, wallet: lease.wallet) }
            try check(wallet: lease.wallet, operation: operation)
            intentID = nil
            invalidate()
        } catch { fail(error, operation: operation) }
    }

    private func verifyRegistration(wallet: DeviceWalletSummary, operation: UUID) async throws {
        try check(wallet: wallet, operation: operation)
        let registered = try await service.walletRegistration()
        try check(wallet: wallet, operation: operation)
        guard registered.accountId == wallet.accountID, registered.address == wallet.address,
              wallet.canAuthorizeTransactions else { throw FundingJournalError.conflict }
    }

    private func verifySource(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, operation: UUID) async throws {
        try plan.validate(wallet: wallet, now: clock())
        let source = try await preflight.snapshot(wallet: wallet)
        try check(wallet: wallet, operation: operation)
        try source.validate(wallet: wallet, now: clock())
        try plan.validate(wallet: wallet, now: clock())
        let amount = FundingQuantity(plan.quote.amountUnits)
        guard source.usdc >= amount else { throw FundingPreflightError.insufficientUSDC }
        guard source.eth > FundingQuantity(0) else { throw FundingPreflightError.insufficientETH }
        guard source.burnLimit >= amount, source.extensionAllowance >= amount else { throw FundingPreflightError.routeChanged }
    }

    private func check(wallet: DeviceWalletSummary, operation: UUID) throws {
        try Task.checkCancellation()
        guard revision == operation, isEnabled(), service.walletAccountID == wallet.accountID else {
            lease?.invalidate()
            throw DeviceWalletError.accountChanged
        }
    }

    private func fail(_ error: Error, operation: UUID) {
        guard revision == operation else { return }
        lease?.invalidate()
        lease = nil
        signedSource = nil
        state = intentID == nil ? .idle : .recoveryRequired
        if error is CancellationError { errorMessage = nil }
        else if intentID == nil, let error = error as? FundingPreflightError { errorMessage = error.errorDescription }
        else if intentID == nil, let error = error as? CCTPFundingError { errorMessage = error.errorDescription }
        else { errorMessage = (error as? FundingJournalError ?? .unavailable).errorDescription }
    }
}
