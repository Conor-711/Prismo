import SwiftUI

struct CCTPDepositEstimateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var fees = CCTPQuoteStore()
    @State private var amount = ""
    @State private var requestID = UUID()
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transfer estimate".bSmartLocalized).font(.headline)
                Spacer()
                if fees.isLoading { ProgressView().controlSize(.small) }
                Button { requestID = UUID() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                .accessibilityLabel("Refresh fees".bSmartLocalized)
                .accessibilityIdentifier("deposit.refresh-fees")
                .disabled(fees.isLoading)
            }
            HStack(spacing: 12) {
                TextField("Amount".bSmartLocalized, text: $amount)
                    .keyboardType(.decimalPad).focused($isEditing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("deposit.estimate-amount")
                    .onChange(of: amount) { _, value in
                        if value.count > 32 { amount = String(value.prefix(32)) }
                    }
                Text("USDC").font(.subheadline.weight(.semibold)).foregroundStyle(BSmartColor.secondaryText)
            }
            .padding(14)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 12) { estimate(at: context.date) }
            }
            row("Arbitrum network fee", value: "ETH (\("Before signing".bSmartLocalized))")
            Text("This estimate covers CCTP fees only. Account activation charges and the final credited amount require separate verification.".bSmartLocalized)
                .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
        }
        .task(id: requestID) { await fees.refresh() }
        .onDisappear { fees.clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { requestID = UUID() } else { fees.clear(); isEditing = false }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done".bSmartLocalized) { isEditing = false }
            }
        }
    }

    @ViewBuilder private func estimate(at now: Date) -> some View {
        if let error = fees.error {
            failure(error)
        } else if let schedule = fees.schedule {
            if (try? schedule.validate(now: now)) == nil {
                failure(.expiredQuote)
            } else if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row("CCTP forwarding fee", value: usdc(schedule.forwardingFeeUnits))
            } else {
                switch Result(catching: { try CCTPDepositQuote(amount: amount, schedule: schedule, now: now) }) {
                case .success(let quote):
                    row("Net after estimated CCTP fees", value: usdc(quote.estimatedCreditUnits))
                    row("Maximum transfer fee", value: usdc(quote.maximumFeeUnits))
                    row("Net at maximum CCTP fee", value: usdc(quote.minimumCreditUnits))
                case .failure(let error): failure((error as? CCTPFundingError) ?? .invalidAmount)
                }
            }
        } else {
            row("CCTP forwarding fee", value: "--")
        }
    }

    private func usdc(_ units: UInt64) -> String { ArbitrumDepositPolicy.formatted(units) + " USDC" }

    private func row(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Spacer(minLength: 12)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }.fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }
        }.font(.subheadline)
    }

    private func failure(_ error: CCTPFundingError) -> some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            .accessibilityIdentifier("deposit.estimate-error")
    }
}
