import SwiftUI

struct SocialMessageRow: View {
    let message: SocialMessage
    let room: SocialChatRoom
    let maxWidth: CGFloat
    let onReply: () -> Void
    let onQuote: (UUID) -> Void
    let onImage: (SocialMessageImage) -> Void
    let onOpenProfile: (FeedPublicProfile) -> Void
    let onOpenShare: (SocialSharedContent) -> Void
    @State private var drag: CGFloat = 0

    private var author: FeedPublicProfile? { message.sender ?? room.peer }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine { Spacer(minLength: 40) }
            else if let author {
                Button { onOpenProfile(author) } label: {
                    BSmartAvatar(url: author.avatarURL, name: author.nickname,
                                 size: room == .global ? 42 : 30)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View profile".bSmartLocalized + ": " + author.nickname)
                .accessibilityIdentifier("friends.message.profile.\(author.id.uuidString)")
            }
            bubble
                .frame(maxWidth: maxWidth, alignment: message.isMine ? .trailing : .leading)
                .offset(x: drag)
                .background(alignment: .trailing) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .foregroundStyle(BSmartColor.brand).opacity(Double(-drag / 64))
                        .padding(.trailing, 12)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 22)
                    .onChanged { value in
                        guard value.translation.width < 0,
                              abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        drag = max(-72, value.translation.width * 0.75)
                    }.onEnded { value in
                        if drag <= -44 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onReply()
                        }
                        withAnimation(.easeOut(duration: 0.18)) { drag = 0 }
                    })
                .contextMenu {
                    Button(action: onReply) { Label("Reply".bSmartLocalized, systemImage: "arrowshape.turn.up.left") }
                    if !message.text.isEmpty {
                        Button { UIPasteboard.general.string = message.text } label: {
                            Label("Copy".bSmartLocalized, systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.text) { Label("Share".bSmartLocalized, systemImage: "square.and.arrow.up") }
                    }
                    if let image = message.image {
                        Button { onImage(image) } label: {
                            Label("View photo".bSmartLocalized, systemImage: "photo")
                        }
                    }
                }
                .accessibilityAction(named: "Reply".bSmartLocalized, onReply)
            if !message.isMine { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.message.\(message.id.uuidString)")
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 7) {
            if room == .global && !message.isMine, let author {
                Button { onOpenProfile(author) } label: {
                    Text(author.nickname).font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand).lineLimit(1)
                }.buttonStyle(.plain)
            }
            if let reply = message.reply {
                Button { onQuote(reply.id) } label: {
                    SocialReplyPreview(name: reply.senderName, text: reply.preview)
                        .padding(8).background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            if let image = message.image {
                Button { onImage(image) } label: {
                    AsyncImage(url: image.url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark") }
                        else { ProgressView() }
                    }
                    .frame(width: maxWidth - 24, height: min(280, max(100, (maxWidth - 24) * CGFloat(image.height) / CGFloat(image.width))))
                    .clipped().background(BSmartColor.recessed)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityLabel("View photo".bSmartLocalized)
            }
            if let share = message.share {
                Button { onOpenShare(share) } label: {
                    SocialSharedContentCard(content: share)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("friends.message.share.\(message.id.uuidString)")
                timestamp.frame(maxWidth: .infinity, alignment: .trailing)
            } else { ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    if !message.text.isEmpty { Text(message.text).fixedSize(horizontal: true, vertical: true) }
                    if message.image != nil || message.reply != nil { Spacer(minLength: 0) }
                    timestamp
                }
                VStack(alignment: .trailing, spacing: 4) {
                    if !message.text.isEmpty {
                        Text(message.text).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    timestamp
                }
            }
            .font(.body).foregroundStyle(BSmartColor.primaryText)
            .frame(maxWidth: message.image != nil || message.reply != nil ? .infinity : nil, alignment: .trailing)
            }
        }
        .padding(12)
        .background(message.isMine ? BSmartColor.brand.opacity(0.16) : BSmartColor.surface,
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var timestamp: some View {
        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2).foregroundStyle(BSmartColor.secondaryText).fixedSize()
    }
}

struct SocialSharedContentCard: View {
    let content: SocialSharedContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(BSmartColor.brand)
                Text(label.bSmartLocalized).foregroundStyle(BSmartColor.brand)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(BSmartColor.tertiaryText)
            }
            .font(.caption.weight(.semibold))
            HStack(spacing: 10) {
                if content.kind != .ticker {
                    BSmartAvatar(url: content.avatarURL, name: content.title, size: 38)
                        .accessibilityIdentifier("chat.shared-avatar")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.primaryText).lineLimit(1)
                    if !content.detail.isEmpty {
                        Text(content.detail).font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if let summary = content.summary, !summary.isEmpty {
                Text(summary).font(.subheadline).foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            if content.ticker != nil || content.publishedAt != nil {
                HStack(spacing: 8) {
                    if let ticker = content.ticker {
                        BSmartAssetMark(ticker: String(ticker.split(separator: ":").last ?? Substring(ticker)), size: 24)
                            .accessibilityIdentifier("chat.shared-logo")
                        Text(ticker).font(.caption.weight(.bold)).foregroundStyle(BSmartColor.brand)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let raw = content.publishedAt, let date = ISO8601DateFormatter().date(from: raw) {
                        Text(date.bSmartDataTimestamp).font(.caption2).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BSmartColor.line, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.shared-card.\(content.kind.rawValue)")
    }

    private var icon: String {
        switch content.kind { case .opinion: "text.bubble"; case .investor: "person.crop.circle"; case .ticker: "chart.xyaxis.line" }
    }
    private var label: String {
        switch content.kind { case .opinion: "Opinion"; case .investor: "Investor"; case .ticker: "Ticker" }
    }
}

struct SocialReplyPreview: View {
    let name: String
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(BSmartColor.brand).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(BSmartColor.brand).lineLimit(1)
                Text(text).font(.subheadline).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct SocialChatPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let image: SocialMessageImage
    var body: some View {
        NavigationStack {
            AsyncImage(url: image.url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else if phase.error != nil { ContentUnavailableView("Photo unavailable".bSmartLocalized, systemImage: "photo") }
                else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(BSmartColor.ink)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".bSmartLocalized) { dismiss() } } }
        }.bSmartPage()
    }
}
