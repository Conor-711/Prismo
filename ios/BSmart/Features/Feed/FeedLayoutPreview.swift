#if DEBUG
import SwiftUI

/// Explicit UI-test surface only. No auth or order submission.
struct FeedLayoutPreview: View {
    @EnvironmentObject private var model: AppModel
    @State private var refresh = 0

    var body: some View {
        NavigationStack {
            DiscoverContent(content: {
                AbilityLeaderboardView(
                    refresh: refresh,
                    snapshotOverride: .mock(accounts: model.smartAccounts,
                                       subjects: model.subjectActivitySnapshot.subjects)
                )
            }, refresh: { refresh += 1 })
            .navigationTitle("Leaderboard".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .bSmartPage()
        }
    }
}
#endif
