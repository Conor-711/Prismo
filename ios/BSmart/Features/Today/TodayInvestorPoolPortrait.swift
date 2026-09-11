import SwiftUI

struct TodayInvestorPoolPortrait: View {
    let investor: TodayInvestorDiscovery.Investor
    let distance: Int
    var compact = false
    let cellWidth: CGFloat
    let onSelect: () -> Void
    private var prominent: Bool { distance == 0 }
    private var size: CGFloat {
        switch distance {
        case 0: min(compact ? 82 : 98, cellWidth * 1.18)
        case 1: min(compact ? 46 : 54, cellWidth * 0.61)
        default: min(compact ? 32 : 38, cellWidth * 0.45)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                BSmartAvatar(url: investor.account.avatarURL, name: investor.account.name, size: size)
                    .padding(prominent ? 4 : 2)
                    .overlay {
                        Circle().stroke(prominent ? BSmartColor.brand.opacity(0.7) : BSmartColor.line,
                                        lineWidth: prominent ? 1.5 : 0.5)
                    }
                    .overlay(alignment: .bottom) {
                        SmartPlatformMark(platform: investor.account.platform, size: prominent ? 20 : 15)
                            .padding(3)
                            .background(BSmartColor.ink, in: Circle())
                            .offset(y: 7)
                    }
                    .frame(height: compact ? 112 : 136)
                Group {
                    if prominent {
                        Text("Top %d%%".bSmartLocalized(TodayInvestorPool.topPercent(investor)))
                            .font(.system(size: compact ? 19 : 21, weight: .bold, design: .rounded))
                            .foregroundStyle(BSmartColor.brand)
                            .fixedSize()
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 28)
            }
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(investor.account.name), \(investor.account.handle), \(investor.account.platform)")
        .accessibilityValue("%@ · Top %d%%".bSmartLocalized(investor.account.platform, TodayInvestorPool.topPercent(investor)))
        .accessibilityAddTraits(prominent ? .isSelected : [])
        .accessibilityIdentifier("discovery.person.\(investor.id)")
    }
}
