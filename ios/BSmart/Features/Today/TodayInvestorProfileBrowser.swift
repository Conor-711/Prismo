import SwiftUI

struct TodayInvestorProfileBrowser: View {
    @State var session: TodayInvestorDiscoverySession

    var body: some View {
        NavigationStack {
            if let investor = session.current {
                SmartAccountDetailView(account: investor.account)
                    .id(investor.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 2) {
                                Button { session.move(by: -1) } label: {
                                    Image(systemName: "chevron.left").frame(width: 36, height: 44)
                                }
                                .disabled(!session.hasPrevious)
                                .accessibilityLabel("Previous investor".bSmartLocalized)
                                .accessibilityIdentifier("discovery.browser.previous")
                                Text("\(session.index + 1) / \(session.investors.count)")
                                    .font(.caption2.monospacedDigit())
                                    .accessibilityIdentifier("discovery.browser.count")
                                Button { session.move(by: 1) } label: {
                                    Image(systemName: "chevron.right").frame(width: 36, height: 44)
                                }
                                .disabled(!session.hasNext)
                                .accessibilityLabel("Next investor".bSmartLocalized)
                                .accessibilityIdentifier("discovery.browser.next")
                            }
                            .foregroundStyle(BSmartColor.primaryText)
                        }
                    }
                    .accessibilityIdentifier("discovery.browser.\(investor.id)")
            }
        }
    }
}
