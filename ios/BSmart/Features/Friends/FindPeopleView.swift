import SwiftUI

struct FindPeopleView: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.dismiss) private var dismiss
    @Binding var snapshot: SocialSnapshot
    let openChat: (FeedPublicProfile) -> Void
    @State private var query = ""
    @State private var people: [FeedPublicProfile] = []
    @State private var loading = false
    @State private var failed = false
    @State private var changing = Set<UUID>()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BSmartColor.secondaryText)
                    TextField("Search people".bSmartLocalized, text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searchFocused)
                        .accessibilityIdentifier("friends.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear".bSmartLocalized)
                    }
                }
                .padding(12).frame(minHeight: 48)
                .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20).padding(.bottom, 14)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(query.isEmpty ? "Discover people".bSmartLocalized : "Results".bSmartLocalized)
                            .font(.headline).padding(.bottom, 8)
                        if loading && people.isEmpty { BSmartSkeletonRows(style: .chat, count: 4) }
                        if failed {
                            Button("Could not load people. Retry".bSmartLocalized) { Task { await search() } }
                                .padding(.vertical, 24)
                        } else if !loading && people.isEmpty {
                            Text(query.isEmpty ? "No people to show".bSmartLocalized : "No people found".bSmartLocalized)
                                .foregroundStyle(BSmartColor.secondaryText).padding(.vertical, 24)
                        }
                        ForEach(people) { person in
                            HStack(spacing: 4) {
                                SocialPersonLabel(profile: person, subtitle: "@\(person.handle ?? "")")
                                Button { Task { await toggleFollow(person) } } label: {
                                    Image(systemName: isFollowing(person.id) ? "checkmark" : "person.badge.plus")
                                        .frame(width: 44, height: 44)
                                }
                                .disabled(changing.contains(person.id))
                                .accessibilityLabel((isFollowing(person.id) ? "Unfollow" : "Follow").bSmartLocalized)
                                .accessibilityIdentifier("friends.search.follow.\(person.id.uuidString)")
                                Button { openChat(person) } label: {
                                    Image(systemName: "bubble.left").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Message".bSmartLocalized)
                                .accessibilityIdentifier("friends.search.message.\(person.id.uuidString)")
                            }
                            .frame(minHeight: 72)
                            Divider().overlay(BSmartColor.softDivider)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
            }
            .background(BSmartColor.ink)
            .navigationTitle("Find people".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
        }
        .bSmartPage()
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search()
        }
        .accessibilityIdentifier("friends.find.screen")
    }

    private func isFollowing(_ id: UUID) -> Bool { snapshot.following.contains { $0.id == id } }

    private func search() async {
        guard let id = account.identity?.id else { return }
        loading = true; failed = false
        do {
            let result = try await NativeSocialClient(account: account).people(query: query, accountID: id)
            guard !Task.isCancelled, account.identity?.id == id else { return }
            people = result
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        loading = false
    }

    private func toggleFollow(_ person: FeedPublicProfile) async {
        guard let id = account.identity?.id, changing.insert(person.id).inserted else { return }
        defer { changing.remove(person.id) }
        do {
            snapshot = try await NativeSocialClient(account: account).follow(person.id,
                enabled: !isFollowing(person.id), accountID: id)
            failed = false
        } catch { failed = true }
    }
}
