import SwiftUI

struct TradeThesisComposer: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    let item: TradeFeedItem
    let accountID: UUID
    let onPublished: () -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(item.opinion.ticker).font(.title2.weight(.semibold))
                        Text((item.side == .long ? "Long" : "Short").bSmartLocalized)
                            .foregroundStyle(item.side == .long ? BSmartColor.bull : BSmartColor.bear)
                        Spacer()
                        Text(item.amountLabel).monospacedDigit()
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 200).scrollContentBackground(.hidden)
                        .accessibilityLabel("Your trade thesis".bSmartLocalized)
                        .accessibilityIdentifier("thesis.editor")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Your trade thesis".bSmartLocalized)
                                    .foregroundStyle(BSmartColor.tertiaryText).padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Text("\(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)/1000")
                        .font(.caption.monospacedDigit()).foregroundStyle(BSmartColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.opinion.authorName).font(.subheadline.weight(.semibold))
                        Text(item.opinion.thesis).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }.padding(16).background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 12))
                    if let error { Text(error).font(.callout).foregroundStyle(BSmartColor.bear) }
                }.padding(20)
            }
            .navigationTitle("Publish thesis".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".bSmartLocalized) { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await publish() } } label: {
                        if busy { ProgressView() } else { Text("Publish".bSmartLocalized) }
                    }.disabled(busy || !TradeThesis.validBody(text) || account.identity?.id != accountID)
                        .accessibilityIdentifier("thesis.publish")
                }
            }
            .interactiveDismissDisabled(busy)
            .onChange(of: account.identity?.id) { _, id in if id != accountID { text = ""; dismiss() } }
            .bSmartPage()
        }
    }

    private func publish() async {
        guard !busy, account.identity?.id == accountID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await NativeTradeFeedClient(account: account).publishThesis(tradeID: item.id, body: text, accountID: accountID)
            guard !Task.isCancelled, account.identity?.id == accountID else { return }
            dismiss()
            onPublished()
            account.feedSharingDidChange(accountID: accountID)
        } catch {
            guard account.identity?.id == accountID else { return }
            self.error = (error as? TradeThesisError)?.message ?? TradeThesisError.unavailable.message
        }
    }
}
