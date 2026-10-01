import SwiftUI

struct TodayInvestorProfileBrowser: View {
    let session: TodayInvestorDiscoverySession

    var body: some View {
        if let investor = session.current {
            SmartAccountDetailView(account: investor.account)
                .id(investor.id)
                .accessibilityIdentifier("discovery.browser.\(investor.id)")
        }
    }
}
