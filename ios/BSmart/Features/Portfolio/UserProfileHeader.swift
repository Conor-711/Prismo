import SwiftUI

struct UserProfileHeader: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @StateObject private var store = LocalUserProfileStore()
    @State private var editing = false
    @State private var showingAddress = false

    private var address: ProfileAddress { ProfileAddress(accountID: account.identity?.id, wallet: wallet.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                UserProfileAvatar(data: store.profile.avatarData, size: 68)
                    .accessibilityLabel("Profile photo".bSmartLocalized)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.profile.displayName)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("profile.nickname")
                    if !store.profile.bio.isEmpty {
                        Text(store.profile.bio).font(.subheadline)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("profile.bio")
                    }
                }
                Spacer(minLength: 0)
                Button { editing = true } label: {
                    Image(systemName: "pencil").font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(BSmartColor.surface, in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                .accessibilityLabel("Edit profile".bSmartLocalized)
                .accessibilityIdentifier("profile.edit")
            }
            Button { showingAddress = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "at").foregroundStyle(BSmartColor.secondaryText)
                    Text(address.shortValue).font(.system(size: 12, weight: .medium, design: .monospaced))
                    if address.isExample {
                        Text("Example address".bSmartLocalized).font(.caption2.weight(.medium))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(BSmartColor.primaryText)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("profile.address")
            Divider().overlay(BSmartColor.line)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.header")
        .task(id: account.identity?.id) { store.load(accountID: account.identity?.id) }
        .onChange(of: account.identity?.id) { _, _ in
            editing = false
            showingAddress = false
            store.load(accountID: account.identity?.id)
        }
        .sheet(isPresented: $editing) {
            UserProfileEditor(store: store)
        }
        .sheet(isPresented: $showingAddress) {
            ProfileAddressSheet(address: address)
                .presentationDetents([.medium])
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

private struct ProfileAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let address: ProfileAddress
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text((address.isExample ? "Example address" : "Account address").bSmartLocalized)
                    .font(.headline)
                Text(address.value).font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.address.full")
                if address.isExample {
                    Label("Display example only. Do not send funds to this address.".bSmartLocalized,
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        .accessibilityIdentifier("profile.address.example-warning")
                } else {
                    Button {
                        UIPasteboard.general.string = address.value
                        copied = true
                    } label: {
                        Label((copied ? "Copied" : "Copy address").bSmartLocalized,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.tint(BSmartColor.brand).accessibilityIdentifier("profile.address.copy")
                }
                Spacer(minLength: 0)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.ink)
            .navigationTitle("Account address".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".bSmartLocalized) { dismiss() } } }
        }
        .bSmartPage()
    }
}
