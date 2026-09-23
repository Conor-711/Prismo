import SwiftUI

struct UserProfileHeader: View {
    @EnvironmentObject private var account: AccountAccessStore
    @StateObject private var store = LocalUserProfileStore()
    @StateObject private var cloud = AccountProfileStore()
    @State private var editing = false

    private var profile: AccountProfile? { cloud.accountID == account.identity?.id ? cloud.profile : nil }
    private var name: String { account.identity == nil ? store.profile.displayName : profile?.username ?? "bSmart Investor".bSmartLocalized }
    private var bio: String { account.identity == nil ? store.profile.bio : profile?.bio ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if account.identity == nil {
                        UserProfileAvatar(data: store.profile.avatarData, size: 76)
                    } else {
                        BSmartAvatar(url: profile?.avatarURL, name: name, size: 76)
                    }
                }
                .padding(5)
                .background(BSmartColor.surface, in: Circle())
                .overlay(Circle().strokeBorder(BSmartColor.brand.opacity(0.16), lineWidth: 1))
                .accessibilityLabel("Profile photo".bSmartLocalized)
                .accessibilityIdentifier("profile.avatar")
                .overlay(alignment: .bottomTrailing) {
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(BSmartColor.elevated, in: Circle())
                            .overlay(Circle().strokeBorder(BSmartColor.ink, lineWidth: 2))
                    }
                    .buttonStyle(.plain).foregroundStyle(BSmartColor.primaryText)
                    .accessibilityLabel("Edit profile".bSmartLocalized)
                    .accessibilityIdentifier("profile.edit")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(.title, design: .default, weight: .semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.nickname")
                    if let handle = profile?.handle {
                        Text("@" + handle).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(1).truncationMode(.middle).accessibilityIdentifier("profile.handle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProfileAssistantLauncher()
            }
            if !bio.isEmpty {
                Text(bio).font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("profile.bio")
            }
            if account.identity != nil {
                if cloud.loading { ProgressView() }
                if cloud.failed {
                    Button("Profile is unavailable. Please try again.".bSmartLocalized) {
                        Task { await cloud.load(account: account) }
                    }.font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
            }
        }
        .padding(.top, 20).padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.header")
        .task(id: account.identity?.id) { store.load(accountID: account.identity?.id) }
        .task(id: "\(account.identity?.id.uuidString ?? "guest"):\(account.feedRevision)") { await cloud.load(account: account) }
        .onChange(of: account.identity?.id) { _, _ in
            editing = false
            store.load(accountID: account.identity?.id)
            cloud.clear()
        }
        .sheet(isPresented: $editing) {
            if let id = account.identity?.id { AccountProfileEditorPage(accountID: id) }
            else { UserProfileEditor(store: store) }
        }
    }
}

struct UserProfileAvatar: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(BSmartColor.brand.opacity(0.12))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.44, weight: .medium))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(BSmartColor.line, lineWidth: 1))
    }
}
