import SwiftUI

struct SocialChatView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var phase
    let room: SocialChatRoom
    let onActivity: () -> Void
    var onMessages: ([SocialMessage]) -> Void = { _ in }
    @State private var messages: [SocialMessage] = []
    @State private var olderCursor: SocialMessagesPage?
    @State private var loading = true
    @State private var loadingOlder = false
    @State private var failed = false
    @State private var olderFailed = false
    @State private var refreshInFlight = false
    @State private var refreshState = SocialChatRefreshState()
    @State private var reply: SocialMessage?
    @State private var selectedImage: SocialMessageImage?
    @State private var selectedProfile: FeedPublicProfile?
    @State private var selectedShare: SocialSharedContent?
    @State private var dismissKeyboard = 0
    @State private var atBottom = true
    @State private var sentID: UUID?
    @State private var viewedAccount: UUID?
    @State private var viewedRoom: String?
    @State private var mediaRefreshedAt = Date.distantPast

    private var refreshKey: String { "\(room.id)-\(account.identity?.id.uuidString ?? "guest")-\(phase == .active)" }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if olderCursor?.hasMore == true {
                            Button((olderFailed ? "Messages unavailable. Retry" : "Load earlier messages").bSmartLocalized) {
                                Task {
                                    let anchor = messages.first?.id
                                    await loadOlder()
                                    if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                }
                            }
                                .font(.subheadline)
                                .foregroundStyle(olderFailed ? BSmartColor.bear : BSmartColor.brand)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .disabled(loadingOlder)
                        }
                        if (loading || refreshState.consecutiveFailures > 0) && messages.isEmpty && !failed {
                            BSmartSkeletonRows(style: .chat, count: 3)
                        } else if messages.isEmpty && !failed {
                            ContentUnavailableView("Start a conversation".bSmartLocalized,
                                                   systemImage: "bubble.left.and.bubble.right")
                        }
                        ForEach(messages) { message in
                            SocialMessageRow(message: message, room: room,
                                maxWidth: max(120, min(520, geometry.size.width - (room == .global ? 92 : 80))),
                                onReply: { reply = message },
                                onQuote: { id in
                                    if messages.contains(where: { $0.id == id }) {
                                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                                    } else { Task { await findQuote(id, proxy: proxy) } }
                                }, onImage: { selectedImage = $0 },
                                onOpenProfile: { selectedProfile = $0 }, onOpenShare: { selectedShare = $0 })
                                .id(message.id)
                        }
                        if failed {
                            Button("Messages unavailable. Retry".bSmartLocalized) { Task { await refresh() } }
                                .font(.subheadline).foregroundStyle(BSmartColor.bear)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        Color.clear.frame(height: 1).id("chat.bottom")
                            .onAppear { atBottom = true }.onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard += 1 })
                .onChange(of: messages.last?.id) { old, _ in
                    if old == nil || atBottom { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                }
                .onChange(of: sentID) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                }
                .onChange(of: geometry.size.height) { _, _ in
                    if atBottom { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    SocialChatComposer(reply: $reply, dismissKeyboard: dismissKeyboard, send: send)
                        .id(account.identity?.id)
                }
            }
        }
        .background(BSmartColor.ink)
        .navigationTitle(room.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .bSmartDetailPage().bSmartPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.chat.screen")
        .sheet(item: $selectedImage) { SocialChatPhotoView(image: $0) }
        .navigationDestination(item: $selectedProfile) { person in
            FeedPublicProfileView(profileID: person.id)
        }
        .navigationDestination(item: $selectedShare) { content in
            SocialSharedContentDestination(content: content)
        }
        .task(id: refreshKey) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-chat-fixture") {
                if messages.isEmpty { messages = SocialChatPreviewData.messages }
                onMessages(messages)
                return
            }
#endif
            if viewedAccount != account.identity?.id || viewedRoom != room.id {
                messages = []; olderCursor = nil; reply = nil; selectedImage = nil
                failed = false; olderFailed = false; refreshState = .init()
                loading = account.identity != nil
                viewedAccount = account.identity?.id; viewedRoom = room.id
            }
            guard account.identity != nil else { loading = false; return }
            guard phase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onDisappear { onActivity() }
    }

    private func refresh() async {
        guard !refreshInFlight, let id = account.identity?.id else { return }
        let requestedRoom = room.id
        refreshInFlight = true
        if messages.isEmpty && !failed { loading = true }
        defer { loading = false; refreshInFlight = false }
        do {
            let page = try await NativeSocialClient(account: account).chat(room, accountID: id)
            guard !Task.isCancelled, account.identity?.id == id, viewedRoom == requestedRoom else { return }
            if messages.isEmpty { olderCursor = page }
            merge(page.items)
            onMessages(page.items)
            refreshState.succeeded(); failed = false
        } catch {
            if !Task.isCancelled && account.identity?.id == id && viewedRoom == requestedRoom {
                failed = refreshState.failed(hasMessages: !messages.isEmpty)
            }
        }
    }

    private func loadOlder() async {
        guard !loadingOlder, let id = account.identity?.id, let cursor = olderCursor, cursor.hasMore else { return }
        let requestedRoom = room.id
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await NativeSocialClient(account: account).chat(room, before: cursor, accountID: id)
            guard !Task.isCancelled, account.identity?.id == id, viewedRoom == requestedRoom else { return }
            olderCursor = page; merge(page.items); olderFailed = false
        } catch { if !Task.isCancelled && account.identity?.id == id && viewedRoom == requestedRoom { olderFailed = true } }
    }

    private func findQuote(_ id: UUID, proxy: ScrollViewProxy) async {
        // Bound network work; the older-page control remains available for distant quotes.
        for _ in 0..<5 {
            guard olderCursor?.hasMore == true, !loadingOlder, !Task.isCancelled else { return }
            await loadOlder()
            if messages.contains(where: { $0.id == id }) {
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                return
            }
            if olderFailed { return }
        }
    }

    private func merge(_ incoming: [SocialMessage]) {
        // Signed avatar URLs rotate; immutable messages need not re-render every poll.
        let refreshMedia = Date().timeIntervalSince(mediaRefreshedAt) > 240
        let next = SocialMessageMerge.merge(messages, incoming, refreshExisting: refreshMedia)
        if refreshMedia { mediaRefreshedAt = Date() }
        if next != messages { messages = next }
    }

    private func send(_ draft: SocialChatDraft) async throws {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-chat-fixture") {
            let quoted = messages.first { $0.id == draft.replyToID }
            let message = SocialMessage(id: draft.id, isMine: true, text: draft.text, sentAt: Date(),
                reply: quoted.map { .init(id: $0.id, senderName: $0.sender?.nickname ?? "Alice", text: $0.text, hasImage: false) })
            merge([message]); sentID = message.id
            onMessages([message])
            return
        }
#endif
        guard let id = account.identity?.id else { throw AccountAccessError.expired }
        let message = try await NativeSocialClient(account: account).send(draft, room: room, accountID: id)
        guard account.identity?.id == id else { throw AccountAccessError.expired }
        merge([message]); sentID = message.id
        onMessages([message])
        refreshState.succeeded(); failed = false
    }
}

private struct SocialSharedContentDestination: View {
    @EnvironmentObject private var model: AppModel
    let content: SocialSharedContent

    var body: some View {
        Group {
            switch content.kind {
            case .opinion:
                if let id = UUID(uuidString: content.id), let update = model.accountUpdate(id: id) {
                    SmartAccountEvidenceDetailView(update: update)
                } else { unavailable }
            case .investor:
                if let account = model.smartAccounts.first(where: { $0.id == content.id }) {
                    SmartAccountDetailView(account: account)
                } else { unavailable }
            case .ticker:
                TickerDestinationView(symbol: content.ticker ?? content.id)
            }
        }
        .navigationTitle(content.title)
    }

    private var unavailable: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SocialSharedContentCard(content: content)
                Text("This item is not in the current catalog.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                if let ticker = content.ticker {
                    NavigationLink { TickerDestinationView(symbol: ticker) } label: {
                        Label("View ticker".bSmartLocalized, systemImage: "chart.xyaxis.line")
                    }
                }
            }.padding(20)
        }.bSmartPage()
    }
}

struct ShareToChatSheet: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    let content: SocialSharedContent
    @State private var snapshot = SocialSnapshot.empty
    @State private var search = ""
    @State private var results: [FeedPublicProfile] = []
    @State private var loading = false
    @State private var sendingRoom: String?
    @State private var attemptIDs: [String: UUID] = [:]
    @State private var errorMessage: String?

    private var peers: [FeedPublicProfile] {
        let listed = search.isEmpty ? snapshot.conversations.map(\.profile) + snapshot.following.map(\.profile) : results
        var seen = Set<UUID>()
        return listed.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SocialSharedContentCard(content: content)
                        .accessibilityIdentifier("chat.share.preview")
                    if account.identity == nil {
                        NavigationLink { TradingAccountView() } label: {
                            Label("Sign in".bSmartLocalized, systemImage: "person.crop.circle")
                        }
                    } else {
                        Text("Send to".bSmartLocalized).font(.headline)
                        destination(.global)
                        TextField("Search people".bSmartLocalized, text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 6))
                        if loading { BSmartSkeletonRows(style: .chat, count: 3) }
                        ForEach(peers) { peer in destination(.direct(peer)) }
                        if peers.isEmpty && !loading && search.isEmpty {
                            Text("Search for a person to share privately.".bSmartLocalized)
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(BSmartColor.bear)
                    }
                }.padding(20)
            }
            .navigationTitle("Share to chat".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .bSmartPage()
        .task(id: account.identity?.id) {
            guard let id = account.identity?.id else { return }
            loading = true
            defer { loading = false }
            do { snapshot = try await NativeSocialClient(account: account).snapshot(accountID: id) }
            catch { errorMessage = "People unavailable. Search or try again.".bSmartLocalized }
        }
        .task(id: search) {
            results = []
            guard let id = account.identity?.id, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            loading = true
            defer { loading = false }
            do { results = try await NativeSocialClient(account: account).people(query: search, accountID: id) }
            catch { errorMessage = "People unavailable. Search or try again.".bSmartLocalized }
        }
    }

    private func destination(_ room: SocialChatRoom) -> some View {
        Button { Task { await send(to: room) } } label: {
            HStack(spacing: 12) {
                if let peer = room.peer {
                    BSmartAvatar(url: peer.avatarURL, name: peer.nickname, size: 42)
                } else {
                    Image(systemName: "globe").font(.title3).foregroundStyle(BSmartColor.brand)
                        .frame(width: 42, height: 42)
                }
                Text(room.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText).lineLimit(1)
                Spacer()
                if sendingRoom == room.id { ProgressView() }
                else { Image(systemName: "arrow.up.right").foregroundStyle(BSmartColor.secondaryText) }
            }.frame(minHeight: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sendingRoom != nil)
        .accessibilityIdentifier("chat.share.destination.\(room.id)")
    }

    private func send(to room: SocialChatRoom) async {
        guard sendingRoom == nil, let id = account.identity?.id else { return }
        guard content.isValid else {
            errorMessage = "This item cannot be shared.".bSmartLocalized
            return
        }
        sendingRoom = room.id; errorMessage = nil
        defer { sendingRoom = nil }
        let attemptID = attemptIDs[room.id] ?? UUID()
        attemptIDs[room.id] = attemptID
        let draft = SocialChatDraft(id: attemptID, text: content.preview, replyToID: nil,
                                    imageBase64: nil, share: content)
        do {
            _ = try await NativeSocialClient(account: account).send(draft, room: room, accountID: id)
            guard account.identity?.id == id else { return }
            attemptIDs[room.id] = nil
            dismiss()
        } catch {
            errorMessage = "Message not sent. Please try again.".bSmartLocalized
        }
    }
}
