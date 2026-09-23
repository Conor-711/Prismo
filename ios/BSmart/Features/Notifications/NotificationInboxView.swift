import SwiftUI

struct NotificationInboxView: View {
    enum Filter: String, CaseIterable {
        case all = "All notifications"
        case tracked = "Tracked activity"
        case holdings = "Holdings updates"
        case followers = "New followers"
    }
    @ObservedObject var inbox: ActivityNotificationStore
    let loading: Bool
    let error: String?
    let refresh: () async -> Void
    var followersLoading = false
    var followersError: String? = nil
    @State private var filter = Filter.all
    @State private var unreadOnly = false
    @State private var addingPosition = false
    @State private var selectedNotification: ActivityNotification?
    private var displayed: [ActivityNotification] {
        inbox.items.filter {
            (!unreadOnly || !inbox.isRead($0)) &&
                (filter == .all || (filter == .tracked && $0.tracked) ||
                    (filter == .holdings && $0.held) || (filter == .followers && $0.isFollow))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                filters.padding(.bottom, 16)
                if let message = filter == .followers ? followersError : error ?? followersError {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(BSmartColor.gold).padding(.bottom, 12)
                }
                if (filter == .followers ? followersLoading : loading || followersLoading) && displayed.isEmpty {
                    BSmartSkeletonRows(style: .feed, count: 3)
                } else if displayed.isEmpty {
                    emptyState
                } else {
                    ForEach(displayed) { item in
                        Button {
                            selectedNotification = item
                            inbox.markRead(item)
                        } label: {
                            if case .follower(let person) = item.payload {
                                NotificationFollowerRow(person: person, unread: !inbox.isRead(item))
                            } else {
                                NotificationActivityRow(item: item, unread: !inbox.isRead(item))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notification.row.\(item.id)")
                        Divider().overlay(BSmartColor.line)
                    }
                }
            }
            .padding(.horizontal, BSmartSpacing.large)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Notifications".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { inbox.markAllRead() } label: { Image(systemName: "checkmark.circle") }
                    .disabled(inbox.unreadCount == 0)
                    .accessibilityLabel("Mark all as read".bSmartLocalized)
                    .accessibilityIdentifier("notifications.read-all")
            }
        }
        .refreshable { await refresh() }
        .navigationDestination(item: $selectedNotification) { item in destination(item) }
        .sheet(isPresented: $addingPosition) { AddPositionView() }
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notifications.screen")
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Filter.allCases, id: \.self) { value in
                        Button { filter = value } label: {
                            Text(value.rawValue.bSmartLocalized)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .font(.subheadline.weight(filter == value ? .bold : .medium))
                                .foregroundStyle(filter == value ? BSmartColor.primaryText : BSmartColor.secondaryText)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottomLeading) {
                                    if filter == value { Rectangle().fill(BSmartColor.brand).frame(height: 2) }
                                }
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(filter == value ? .isSelected : [])
                            .accessibilityIdentifier("notifications.filter.\(value)")
                    }
                }
            }
            .accessibilityIdentifier("notifications.filters")
            Button { unreadOnly.toggle() } label: {
                Image(systemName: unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(unreadOnly ? BSmartColor.brand : BSmartColor.secondaryText)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel("Unread only".bSmartLocalized)
                .accessibilityValue((unreadOnly ? "On" : "Off").bSmartLocalized)
                .accessibilityIdentifier("notifications.unread-only")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: unreadOnly ? "checkmark.bubble" : "bell")
                .font(.system(size: 30)).foregroundStyle(BSmartColor.secondaryText)
            Text((unreadOnly ? "You're all caught up" : filter == .followers ? "No new followers yet" : "No relevant notifications yet").bSmartLocalized)
                .font(.headline).foregroundStyle(BSmartColor.primaryText)
            if unreadOnly {
                Button("All notifications".bSmartLocalized) { unreadOnly = false }
            } else if filter != .followers {
                BSmartDetailNavigationLink(id: "notifications-discover") {
                    SmartHubView()
                } label: {
                    Label("Discover smart investors".bSmartLocalized, systemImage: "person.crop.circle.badge.plus")
                }
                Button { addingPosition = true } label: {
                    Label("Add holding".bSmartLocalized, systemImage: "plus")
                }
            }
        }
        .buttonStyle(.plain).tint(BSmartColor.brand)
        .padding(.vertical, 40).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("notifications.empty")
    }

    @ViewBuilder private func destination(_ item: ActivityNotification) -> some View {
        switch item.payload {
        case .account(let update): SmartAccountEvidenceDetailView(update: update)
        case .money(let movement): SmartMoneyMovementDetailView(movement: movement)
        case .follower(let person): FeedPublicProfileView(profileID: person.id)
        }
    }
}

private struct NotificationActivityRow: View {
    let item: ActivityNotification
    let unread: Bool
    private var activity: TodayActivity? {
        switch item.payload {
        case .account(let update): .account(.init(updates: [update]))
        case .money(let movement): .money(.init(movements: [movement]))
        case .follower: nil
        }
    }
    private var name: String {
        switch item.payload {
        case .account(let update): update.authorName
        case .money(let movement): movement.publicIdentity.displayName
        case .follower(let person): person.profile.nickname
        }
    }
    private var headline: String {
        if case .account(let update) = item.payload { return TodaySourceHeadline.account(update).text }
        return activity?.informativeTitle ?? "Started following you".bSmartLocalized
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar.overlay(alignment: .topLeading) {
                if unread {
                    Circle().fill(BSmartColor.brand).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(BSmartColor.ink, lineWidth: 1.5)).offset(x: -3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    platform
                    Spacer(minLength: 4)
                    Text(item.occurredAt.bSmartRelativeTimestamp)
                        .font(.caption2).foregroundStyle(BSmartColor.tertiaryText).lineLimit(1)
                }
                Text(headline).font(.subheadline).lineSpacing(3).lineLimit(4)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if let activity { HStack(spacing: 7) {
                    BSmartAssetMark(ticker: item.ticker, size: 20)
                    Text(item.ticker).font(.caption.weight(.bold)).lineLimit(1)
                    Text(activity.direction.label).font(.caption.weight(.medium)).foregroundStyle(activity.direction.color)
                    Spacer(minLength: 4)
                    if item.tracked { Image(systemName: "star.fill").foregroundStyle(BSmartColor.brand).accessibilityLabel("Tracked activity".bSmartLocalized) }
                    if item.held { Image(systemName: "briefcase.fill").foregroundStyle(BSmartColor.sky).accessibilityLabel("Holdings updates".bSmartLocalized) }
                }.font(.caption2) }
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue((unread ? "Unread" : "Read").bSmartLocalized)
    }
    @ViewBuilder private var avatar: some View {
        switch item.payload {
        case .account(let update): BSmartAvatar(url: update.authorAvatarURL, name: name, size: 38)
        case .money(let movement): BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 38)
        case .follower(let person): BSmartAvatar(url: person.profile.avatarURL, name: name, size: 38)
        }
    }
    @ViewBuilder private var platform: some View {
        switch item.payload {
        case .account(let update): SmartPlatformMark(platform: update.platform, size: 13)
        case .money: SmartPlatformMark(platform: "Hyperliquid", size: 13)
        case .follower: EmptyView()
        }
    }
}

private struct NotificationFollowerRow: View {
    let person: SocialPerson
    let unread: Bool

    var body: some View {
        HStack(spacing: 12) {
            BSmartAvatar(url: person.profile.avatarURL, name: person.profile.nickname, size: 44)
                .overlay(alignment: .topLeading) {
                    if unread {
                        Circle().fill(BSmartColor.brand).frame(width: 7, height: 7)
                            .overlay(Circle().stroke(BSmartColor.ink, lineWidth: 1.5))
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(person.profile.nickname).font(.body.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(BSmartColor.primaryText)
                Text("Started following you".bSmartLocalized).font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer(minLength: 4)
            Text(person.at.bSmartRelativeTimestamp).font(.caption)
                .foregroundStyle(BSmartColor.tertiaryText).lineLimit(1)
        }
        .padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
        .accessibilityValue((unread ? "Unread" : "Read").bSmartLocalized)
    }
}
