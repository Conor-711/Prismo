import SwiftUI

private enum FriendsSection: String, CaseIterable {
    case chats = "Chats"
    case activity = "Activity"
}

struct FriendsView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var globalChatUnread: GlobalChatUnreadStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot = SocialSnapshot.empty
    @State private var section = FriendsSection.chats
    @State private var selectedPeer: FeedPublicProfile?
    @State private var showingGlobal = false
    @State private var pendingPeer: FeedPublicProfile?
    @State private var showingFind = false
    @State private var loading = true
    @State private var viewedAccount: UUID?
    @State private var errorMessage: String?
    @Namespace private var tabSelection

    private struct RefreshKey: Hashable {
        let accountID: UUID?
        let active: Bool
    }

    private var refreshKey: RefreshKey {
        .init(accountID: account.identity?.id, active: router.selection == .friends && phase == .active)
    }

    var body: some View {
        NavigationStack {
            BSmartCollapsingPager(
                selection: $section,
                sections: FriendsSection.allCases,
                pageIdentifier: { "friends.page.\($0.rawValue)" },
                header: { _ in header },
                tabs: { sectionPicker },
                content: { item in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let errorMessage {
                            HStack {
                                Text(errorMessage).font(.subheadline).foregroundStyle(BSmartColor.bear)
                                Spacer()
                                Button("Retry".bSmartLocalized) { Task { await refresh() } }
                            }.padding(.bottom, 16)
                        }
                        Group {
                            switch item {
                            case .chats: chats
                            case .activity: activity
                            }
                        }
                    }
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                },
                refresh: { await refresh() }
            )
            .background(BSmartColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedPeer) { peer in
                SocialChatView(room: .direct(peer), onActivity: { Task { await refresh() } }).id(peer.id)
            }
            .navigationDestination(isPresented: $showingGlobal) {
                SocialChatView(room: .global, onActivity: {}, onMessages: { messages in
                    globalChatUnread.markRead(messages)
                })
                .onAppear { globalChatUnread.beginViewing(accountID: account.identity?.id) }
                .onDisappear { globalChatUnread.endViewing() }
            }
            .sheet(isPresented: $showingFind, onDismiss: {
                selectedPeer = pendingPeer
                pendingPeer = nil
            }) {
                FindPeopleView(snapshot: $snapshot, openChat: { profile in
                    pendingPeer = profile
                    showingFind = false
                })
            }
        }
        .bSmartPage()
        .accessibilityIdentifier("friends.screen")
        .task(id: refreshKey) {
            if viewedAccount != refreshKey.accountID {
                snapshot = .empty
                errorMessage = nil
                viewedAccount = refreshKey.accountID
                loading = refreshKey.accountID != nil
            }
            guard refreshKey.accountID != nil else { loading = false; return }
            guard refreshKey.active else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Friends".bSmartLocalized)
                .font(.system(size: 29, weight: .bold))
            Spacer()
            Button { showingFind = true } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Find people".bSmartLocalized)
            .accessibilityIdentifier("friends.find")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
    }

    private var sectionPicker: some View {
        HStack(spacing: 24) {
            ForEach(FriendsSection.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { section = item }
                } label: {
                    Text(item.rawValue.bSmartLocalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(section == item ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .lineLimit(1)
                        .frame(minWidth: 44, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomLeading) {
                            if section == item {
                                Capsule().fill(BSmartColor.pulse).frame(width: 40, height: 3)
                                    .matchedGeometryEffect(id: "friends.selection", in: tabSelection)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
                .accessibilityIdentifier("friends.tab.\(item.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .overlay(alignment: .bottom) { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.section-picker")
    }

    private var chats: some View {
        Group {
            Button { showingGlobal = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe").font(.system(size: 26, weight: .medium))
                        .foregroundStyle(BSmartColor.brand).frame(width: 50, height: 50)
                        .background(BSmartColor.brand.opacity(0.12), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if globalChatUnread.hasUnread {
                                Circle().fill(BSmartColor.bear)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -3, y: 3)
                                    .accessibilityHidden(true)
                            }
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Global Chat".bSmartLocalized).font(.body.weight(.semibold))
                            .foregroundStyle(BSmartColor.primaryText)
                        if let latest = globalChatUnread.latestMessage {
                            (Text(latest.isMine ? "You".bSmartLocalized :
                                  (latest.sender?.nickname ?? "Global Chat".bSmartLocalized))
                                .fontWeight(.semibold) + Text(": \(latest.preview)"))
                            .font(.subheadline)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }.frame(minHeight: 78).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(globalChatUnread.hasUnread ? "Unread messages".bSmartLocalized : "")
            .accessibilityIdentifier("friends.global")
            Divider().overlay(BSmartColor.softDivider)
            if snapshot.conversations.isEmpty {
                if loading { BSmartSkeletonRows(style: .chat, count: 3).padding(.vertical, 12) }
                else { empty("No conversations yet", icon: "bubble.left.and.bubble.right") }
            } else {
                ForEach(snapshot.conversations) { conversation in
                    Button { selectedPeer = conversation.profile } label: {
                        HStack(spacing: 12) {
                            BSmartAvatar(url: conversation.profile.avatarURL,
                                         name: conversation.profile.nickname, size: 50)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conversation.profile.nickname).font(.body.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText).lineLimit(1)
                                Text(conversation.lastMessage.isMine
                                     ? "You: \(conversation.lastMessage.preview)" : conversation.lastMessage.preview)
                                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if conversation.unreadCount > 0 {
                                Text("\(min(conversation.unreadCount, 99))")
                                    .font(.caption2.weight(.bold)).foregroundStyle(BSmartColor.onAccent)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(BSmartColor.brand, in: Circle())
                            }
                        }.frame(minHeight: 72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("friends.chat.\(conversation.id.uuidString)")
                    Divider().overlay(BSmartColor.softDivider)
                }
            }
        }
    }

    private var activity: some View {
        Group {
            let unread = snapshot.conversations.filter { $0.unreadCount > 0 }
            if loading && unread.isEmpty {
                BSmartSkeletonRows(style: .chat, count: 3).padding(.vertical, 12)
            } else if unread.isEmpty {
                empty("No new activity", icon: "bell")
            } else {
                if !unread.isEmpty {
                    heading("Unread messages", count: unread.reduce(0) { $0 + $1.unreadCount })
                    ForEach(unread) { conversation in
                        Button { selectedPeer = conversation.profile } label: {
                            SocialPersonLabel(profile: conversation.profile,
                                subtitle: conversation.lastMessage.text)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(BSmartColor.softDivider)
                    }
                }
            }
        }
    }

    private func heading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.bSmartLocalized).font(.headline)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
        }.padding(.vertical, 12)
    }

    private func empty(_ title: String, icon: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(BSmartColor.secondaryText)
            Text(title.bSmartLocalized).font(.headline)
            Button("Find people".bSmartLocalized) { showingFind = true }
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 230)
    }

    private func refresh() async {
        guard let id = account.identity?.id, router.selection == .friends else { return }
        loading = true
        do {
            let value = try await NativeSocialClient(account: account).snapshot(accountID: id)
            guard !Task.isCancelled, account.identity?.id == id else { return }
            snapshot = value
            errorMessage = nil
        } catch {
            guard account.identity?.id == id else { return }
            errorMessage = "Friends are unavailable. Please try again.".bSmartLocalized
        }
        loading = false
    }

}

struct SocialPersonLabel: View {
    let profile: FeedPublicProfile
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            BSmartAvatar(url: profile.avatarURL, name: profile.nickname, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.nickname).font(.body.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }
}
