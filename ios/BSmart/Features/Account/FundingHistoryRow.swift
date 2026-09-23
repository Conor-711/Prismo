import SwiftUI

struct FundingHistoryRow: View {
    let entry: FundingHistoryEntry
    @Binding var expanded: Bool
    var checkSource: (() -> Void)? = nil
    var checkCrossChain: (() -> Void)? = nil
    let cancel: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var identifierHeight = 30.0

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
                if let notice = entry.forwardingStatus?.notice ?? entry.stage.notice {
                    Label(notice.bSmartLocalized, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                identifier("Wallet", value: entry.owner, copyLabel: "Copy wallet address")
                detail("Maximum transfer fee", value: ArbitrumDepositPolicy.formatted(entry.maximumTransferFeeUnits) + " USDC")
                if let fee = entry.maximumNetworkFee {
                    detail("Maximum network fee", value: fee.formatted(decimals: 18) + " ETH")
                }
                if let fee = entry.sourceNetworkFee {
                    detail("Observed source network fee", value: fee.formatted(decimals: 18) + " ETH")
                }
                if let fee = entry.attestedTransferFee {
                    detail("Attested transfer fee", value: fee.formatted(decimals: 6) + " USDC")
                }
                if let amount = entry.forwardedCoreAmount {
                    detail("Forwarded amount (credit unverified)", value: amount.formatted(decimals: 8) + " USDC")
                }
                if let fee = entry.destinationAccountFee, fee > FundingQuantity(0) {
                    detail("Destination account fee", value: fee.formatted(decimals: 8) + " USDC")
                }
                if let hash = entry.forwardingTransactionHash {
                    identifier("HyperEVM transaction", value: hash, copyLabel: "Copy transaction hash")
                }
                if entry.sourceDataFinalized {
                    Label("Source data finalized (RPC)".bSmartLocalized, systemImage: "server.rack")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
                if let hash = entry.transactionHash {
                    identifier("Transaction hash", value: hash, copyLabel: "Copy transaction hash")
                    if let checkSource, entry.stage.requiresReconciliation,
                       entry.stage != .sourceExecuted || checkCrossChain == nil {
                        Button(action: checkSource) {
                            Label("Check source transaction".bSmartLocalized, systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                            .accessibilityIdentifier("deposit.check-source.\(entry.id.uuidString)")
                    }
                }
                if entry.stage.canCancelReview {
                    Button(action: cancel) {
                        Label("Cancel review".bSmartLocalized, systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                }
                if [.authorizationRecorded, .authorizationStarted, .notSubmitted, .authorizationExpired].contains(entry.stage) {
                    NavigationLink { CCTPTransferDestination() } label: {
                        Label("Continue deposit".bSmartLocalized, systemImage: "arrow.right")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.foregroundStyle(BSmartColor.brand)
                }
                if entry.stage == .sourceExecuted, let checkCrossChain {
                    Button(action: checkCrossChain) {
                        Label("Check cross-chain status".bSmartLocalized, systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                        .accessibilityIdentifier("deposit.check-cross-chain.\(entry.id.uuidString)")
                }
            }
            .padding(.top, 12).padding(.bottom, 8)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(ArbitrumDepositPolicy.formatted(entry.amountUnits) + " USDC")
                    .font(.system(.title3, weight: .semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Label((entry.forwardingStatus?.title ?? entry.attestationStatus?.title ?? entry.stage.title).bSmartLocalized, systemImage: entry.stage.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(entry.stage.requiresReconciliation ? BSmartColor.gold : BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(BSmartLocalization.formattingLocale)))
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
            .padding(.vertical, 18)
        }
        .tint(BSmartColor.secondaryText)
        .multilineTextAlignment(.leading)
        .accessibilityIdentifier("deposit.history-entry.\(entry.id.uuidString)")
    }

    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func identifier(_ title: String, value: String, copyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            HStack(spacing: 8) {
                // One unmodified line avoids the system inserting visual hyphens into a hex identifier.
                ScrollView(.horizontal) {
                    Text(verbatim: value).font(.subheadline.monospaced())
                        .fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                }
                .frame(height: identifierHeight)
                .scrollIndicators(.visible)
                Button { UIPasteboard.general.string = value } label: {
                    Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                .accessibilityLabel(copyLabel.bSmartLocalized)
            }
        }
    }
}

extension FundingHistoryEntry.ForwardingStatus {
    var title: String {
        switch self {
        case .waiting: "Waiting for forwarding receipt"
        case .perpsRequested: "Forwarded to perps; credit unverified"
        case .spotFallback: "Forwarded to spot; review required"
        }
    }
    var notice: String {
        switch self {
        case .waiting: "The destination transaction is not yet verified. Do not send another deposit."
        case .perpsRequested: "HyperEVM forwarding was verified. HyperCore credit and tradable balance still need verification."
        case .spotFallback: "The contract routed this deposit to spot instead of perps. Do not send another deposit or treat it as trading collateral."
        }
    }
}

extension FundingHistoryEntry.AttestationStatus {
    var title: String {
        switch self {
        case .waiting: "Waiting for Circle attestation"
        case .verified: "CCTP signatures verified; credit unverified"
        case .expired: "Attestation expired; deposit still unresolved"
        case .paused: "Destination contract paused; credit unverified"
        case .processed: "CCTP nonce processed; HyperCore credit unverified"
        }
    }
}

extension FundingHistoryEntry.Stage {
    var title: String {
        switch self {
        case .reviewAuthorization: "Awaiting authorization review"
        case .authorizationStarted: "Authorization needs checking"
        case .authorizationRecorded: "Authorization saved"
        case .authorizationExpired: "Authorization expired"
        case .notSubmitted: "Not sent; you can try again"
        case .reviewNetworkFee: "Awaiting network fee review"
        case .signingStarted: "Signing needs checking"
        case .signatureRecorded: "Signed transaction saved"
        case .submissionStarted: "Submission needs checking"
        case .nodeAcknowledged: "Node acknowledged transaction"
        case .submissionUnknown: "Submission status unknown"
        case .cancelled: "Review cancelled"
        case .sourceNotFound: "Transaction not found by node"
        case .sourcePending: "Waiting for source inclusion"
        case .sourceExecuted: "Source executed; credit unverified"
        case .sourceReverted: "Source execution reverted"
        case .sourceReorganized: "Source inclusion changed"
        case .sourceConflict: "Wallet activity needs reconciliation"
        }
    }

    var symbol: String {
        if canCancelReview { return "doc.text.magnifyingglass" }
        return [.cancelled, .authorizationExpired, .notSubmitted].contains(self) ? "xmark.circle" : "clock.badge.exclamationmark"
    }

    var notice: String? {
        switch self {
        case .reviewAuthorization, .cancelled, .authorizationExpired, .notSubmitted: nil
        case .reviewNetworkFee: "The USDC authorization is saved. The network transaction has not been signed."
        case .authorizationStarted, .authorizationRecorded:
            "No transfer was sent. Continue the deposit to resume or refresh this authorization."
        case .signingStarted, .signatureRecorded:
            "A signature may exist. Do not send another deposit until the source transaction is checked."
        case .submissionStarted, .nodeAcknowledged, .submissionUnknown:
            "This is not proof of HyperCore credit. Source execution and destination credit still need verification."
        case .sourceExecuted:
            "The source transaction and CCTP message were verified. HyperCore credit is not yet verified."
        case .sourceNotFound, .sourcePending, .sourceReorganized, .sourceConflict:
            "Source status remains unresolved. Do not send another deposit."
        case .sourceReverted:
            "The source call reverted and incurred a network fee. The record still requires reconciliation before another deposit."
        }
    }
}
