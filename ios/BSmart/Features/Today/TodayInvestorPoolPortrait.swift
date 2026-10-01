import SwiftUI

struct TodayInvestorPoolPortrait: View {
    let investor: TodayInvestorDiscovery.Investor
    let distance: Int
    var compact = false
    let cellWidth: CGFloat
    let onSelect: () -> Void
    private var prominent: Bool { distance == 0 }
    private var rankLabel: String {
        if investor.account.platform == "bsmart" {
            guard investor.account.nativePerformance?.rank != nil else {
                return "Verified trader".bSmartLocalized
            }
            return "bSmart Top \(TodayInvestorPool.topPercent(investor))%"
        }
        return "Top %d%%".bSmartLocalized(TodayInvestorPool.topPercent(investor))
    }
    private var size: CGFloat {
        switch distance {
        case 0: min(compact ? 96 : 108, cellWidth - 14)
        default: min(compact ? 74 : 84, cellWidth - 28)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                BSmartAvatar(url: investor.account.avatarURL, name: investor.account.name,
                             size: size)
                    .padding(prominent ? 4 : 2)
                    .overlay {
                        Circle()
                            .stroke(prominent ? BSmartColor.brand.opacity(0.7) : BSmartColor.line,
                                    lineWidth: prominent ? 1.5 : 0.5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        SmartPlatformMark(platform: investor.account.platform, size: prominent ? 20 : 15)
                            .padding(3)
                            .background(BSmartColor.ink, in: Circle())
                            .offset(x: 5, y: 5)
                    }
                    .frame(height: compact ? 112 : 124)
                Group {
                    if prominent {
                        Text(rankLabel)
                            .font(.system(size: investor.account.platform == "bsmart" && investor.account.nativePerformance?.rank == nil ? 11 : 17,
                                          weight: .bold, design: .rounded))
                            .foregroundStyle(BSmartColor.brand)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 28)
            }
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityLabel("\(investor.account.name), \(investor.account.handle), \(investor.account.platform)")
        .accessibilityValue("\(investor.account.platform) · \(rankLabel)")
        .accessibilityAddTraits(prominent ? .isSelected : [])
        .accessibilityIdentifier("discovery.person.\(investor.id)")
    }
}
