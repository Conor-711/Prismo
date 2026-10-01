import SwiftUI

struct TradeThesisComposer: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    let item: TradeFeedItem
    let accountID: UUID
    let onPublished: () -> Void
    @ObservedObject private var drafts = TradeThesisDraftStore.shared
    @State private var text = ""
    @State private var hasEdited = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(item.opinion.ticker).font(.title2.weight(.semibold))
                        Text((item.opinion.sourceKind == "native_trade" && item.opinion.lifecycle == .closed
                              ? (item.side == .long ? "Close short" : "Close long")
                              : (item.side == .long ? "Long" : "Short")).bSmartLocalized)
                            .foregroundStyle(item.side == .long ? BSmartColor.bull : BSmartColor.bear)
                        Spacer()
                        Text(item.amountLabel).monospacedDigit()
                    }
                    TextEditor(text: Binding(get: { text }, set: { value in
                        guard account.identity?.id == accountID else { return }
                        hasEdited = true
                        text = value
                        drafts.save(value, accountID: accountID, tradeID: item.id)
                    }))
                        .disabled(busy)
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
                    if item.opinion.sourceKind != "native_trade" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.opinion.authorName).font(.subheadline.weight(.semibold))
                            Text(item.opinion.thesis).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        }.padding(16).background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(BSmartColor.bear) }
                    if drafts.failedKeys.contains(.init(accountID: accountID, tradeID: item.id)) {
                        Text("Could not save this draft on your device.".bSmartLocalized)
                            .font(.callout).foregroundStyle(BSmartColor.bear)
                    }
                }.padding(20)
            }
            .navigationTitle("Publish thesis".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Group {
                    Button("Cancel".bSmartLocalized) { dismiss() }.disabled(busy)
                }.buttonStyle(.bSmartToolbar) }.bSmartHideSystemBackground()
                ToolbarItem(placement: .confirmationAction) { Group {
                    Button { Task { await publish() } } label: {
                        if busy { ProgressView() } else { Text("Publish".bSmartLocalized) }
                    }.disabled(busy || !TradeThesis.validBody(text) || account.identity?.id != accountID)
                        .accessibilityIdentifier("thesis.publish")
                }.buttonStyle(.bSmartToolbar) }.bSmartHideSystemBackground()
            }
            .interactiveDismissDisabled(busy)
            .task(id: item.id) {
                guard account.identity?.id == accountID else { return }
                do {
                    let saved = try await drafts.load(accountID: accountID, tradeID: item.id)
                    guard !Task.isCancelled, account.identity?.id == accountID, !hasEdited else { return }
                    text = saved
                } catch {
                    guard !Task.isCancelled, account.identity?.id == accountID else { return }
                    self.error = "Could not restore this draft on your device.".bSmartLocalized
                }
            }
            .onChange(of: account.identity?.id) { _, id in if id != accountID { text = ""; dismiss() } }
            .bSmartPage()
        }
    }

    private func publish() async {
        guard !busy, account.identity?.id == accountID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let submittedText = text
            _ = try await NativeTradeFeedClient(account: account).publishThesis(tradeID: item.id, body: submittedText, accountID: accountID)
            guard !Task.isCancelled, account.identity?.id == accountID else { return }
            drafts.remove(accountID: accountID, tradeID: item.id)
            dismiss()
            onPublished()
            account.feedSharingDidChange(accountID: accountID)
            NotificationCenter.default.post(name: .bSmartNativeInvestorChanged, object: nil)
        } catch {
            guard account.identity?.id == accountID else { return }
            self.error = (error as? TradeThesisError)?.message ?? TradeThesisError.unavailable.message
        }
    }
}
