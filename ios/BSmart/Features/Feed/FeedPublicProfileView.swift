import SwiftUI

/// Resolves legacy public-profile links into the shared subject-detail page.
struct FeedPublicProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    let profileID: UUID
    var demo: TradeFeedDemoData? = nil
    @State private var profile: FeedPublicProfile?
    @State private var failed = false
    @State private var requestID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            if let profile {
                SmartAccountDetailView(
                    account: profile.smartAccount(matching: model.smartAccounts.first { $0.nativeProfileID == profileID }),
                    nativeProfile: profile, nativeDemo: demo)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if failed {
                            Text("Public profile unavailable".bSmartLocalized).font(.headline)
                            Button("Retry".bSmartLocalized) { Task { await loadProfile() } }
                                .buttonStyle(.bSmartSecondary)
                        } else { BSmartSkeletonRows(style: .profile, count: 1) }
                    }.padding(20)
                }
                .navigationTitle("Profile".bSmartLocalized)
                .navigationBarTitleDisplayMode(.inline)
                .bSmartDetailPage().bSmartPage()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.profile.screen")
        .task(id: "\(account.identity?.id.uuidString ?? "signed-out")-\(account.feedRevision)") {
            profile = nil
            await loadProfile()
        }
        .onChange(of: account.identity?.id) { _, _ in profile = nil; requestID = UUID() }
    }

    private func loadProfile() async {
        let token = UUID()
        requestID = token
        let viewerID = account.identity?.id
        failed = false
        do {
            let value: FeedPublicProfile
            if let demo { value = try demo.profile(id: profileID) }
            else { value = try await NativeTradeFeedClient(account: account).profile(profileID) }
            guard !Task.isCancelled, token == requestID, account.identity?.id == viewerID else { return }
            profile = value
        } catch {
            guard !Task.isCancelled, token == requestID, account.identity?.id == viewerID else { return }
            profile = nil
            failed = true
        }
    }
}
