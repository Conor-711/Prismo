import SwiftUI

struct TradeThesisActions: View {
    @EnvironmentObject private var account: AccountAccessStore
    let item: TradeFeedItem
    let onPublished: () -> Void
    @State private var updated: TradeThesis?
    @State private var busy = false
    @State private var composing = false
    @State private var error: String?
    private var thesis: TradeThesis? { updated ?? item.thesis }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thesis {
                Button { Task { await like(thesis) } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: thesis.likedByMe ? "heart.fill" : "heart")
                        Text("\(thesis.likeCount)").monospacedDigit()
                        if busy { ProgressView().controlSize(.small) }
                    }.font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(thesis.likedByMe ? BSmartColor.bear : BSmartColor.secondaryText)
                .disabled(busy || account.identity == nil || item.canLikeThesis != true)
                .accessibilityLabel((thesis.likedByMe ? "Unlike thesis" : "Like thesis").bSmartLocalized)
                .accessibilityValue("\(thesis.likeCount)")
                .accessibilityIdentifier("thesis.like.\(item.id.uuidString)")
            } else if item.canPublishThesis == true {
                Button { composing = true } label: {
                    Label("Write thesis".bSmartLocalized, systemImage: "square.and.pencil")
                        .font(.subheadline).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(BSmartColor.brand)
                    .accessibilityIdentifier("thesis.write.\(item.id.uuidString)")
            }
            if let error { Text(error).font(.callout).foregroundStyle(BSmartColor.bear) }
        }
        .sheet(isPresented: $composing) {
            if let id = account.identity?.id {
                TradeThesisComposer(item: item, accountID: id, onPublished: onPublished)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bSmartTradeThesisUpdated)) { notification in
            guard let change = notification.object as? TradeThesisChange,
                  change.accountID == account.identity?.id, change.thesis.id == item.id else { return }
            updated = change.thesis
        }
        .onChange(of: item.thesis) { _, _ in updated = nil }
        .onChange(of: account.identity?.id) { _, _ in updated = nil; composing = false; error = nil }
    }

    private func like(_ current: TradeThesis) async {
        guard !busy, let id = account.identity?.id else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await NativeTradeFeedClient(account: account)
                .likeThesis(tradeID: item.id, liked: !current.likedByMe, accountID: id)
            guard !Task.isCancelled, account.identity?.id == id else { return }
            updated = value
            NotificationCenter.default.post(name: .bSmartTradeThesisUpdated,
                object: TradeThesisChange(accountID: id, thesis: value))
        } catch {
            guard account.identity?.id == id else { return }
            self.error = (error as? TradeThesisError)?.message ?? TradeThesisError.unavailable.message
        }
    }
}
