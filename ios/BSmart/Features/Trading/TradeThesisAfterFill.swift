import SwiftUI

struct TradeThesisAfterFill: View {
    @EnvironmentObject private var account: AccountAccessStore
    let record: HyperliquidOrderRecord
    let accent: Color
    @State private var item: TradeFeedItem?
    @State private var busy = false
    @State private var published = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            if published {
                Label("Thesis published".bSmartLocalized, systemImage: "checkmark.circle")
                    .foregroundStyle(BSmartColor.brand)
            } else {
                Button { Task { await prepare() } } label: {
                    Group {
                        if busy { ProgressView().tint(BSmartColor.onAccent) }
                        else { Label("Write thesis".bSmartLocalized, systemImage: "square.and.pencil") }
                    }
                    .font(.headline)
                    .foregroundStyle(BSmartColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityIdentifier("trade.thesis.write")
                if let error { Text(error).font(.callout).foregroundStyle(BSmartColor.bear) }
            }
        }
        .sheet(item: $item) { value in
            TradeThesisComposer(item: value, accountID: record.order.accountID) { published = true }
        }
        .onChange(of: account.identity?.id) { _, _ in item = nil; error = nil }
    }

    private func prepare() async {
        guard !busy, account.identity?.id == record.order.accountID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let client = NativeTradeFeedClient(account: account)
            let value = try await client.activityForWriting(cloid: record.order.cloid, accountID: record.order.accountID)
            guard !Task.isCancelled, account.identity?.id == record.order.accountID else { return }
            if value.thesis != nil { published = true }
            else if value.canPublishThesis == true { item = value }
            else { self.error = TradeThesisError.missing.message }
        } catch {
            guard account.identity?.id == record.order.accountID else { return }
            if let thesisError = error as? TradeThesisError, thesisError != .unavailable {
                self.error = thesisError.message
            } else {
                self.error = "Could not load this trade. Please try again.".bSmartLocalized
            }
        }
    }
}
