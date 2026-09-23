import Charts
import SwiftUI

struct TickerChartOpinionOverlay: View {
    let opinions: [TickerChartOpinion]
    let policy: TickerChartOpinionPolicy
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geometry in
            if let plot = proxy.plotFrame {
                let bounds = geometry[plot]
                let placements = TickerChartOpinionPlacement.layout(opinions.compactMap { opinion in
                    guard let x = proxy.position(forX: opinion.date), let y = proxy.position(forY: opinion.price),
                          (0...bounds.width).contains(x), (0...bounds.height).contains(y) else { return nil }
                    return (opinion, CGPoint(x: x + bounds.minX, y: y + bounds.minY))
                }, in: bounds, policy: policy)
                ForEach(placements) { placement in
                    Path { path in
                        path.move(to: placement.anchor)
                        path.addLine(to: CGPoint(x: placement.frame.midX, y: placement.frame.midY))
                    }
                    .stroke(placement.opinion.activity.direction.color.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)

                    BSmartDetailNavigationLink(id: "chart-opinion-\(placement.id)") {
                        TickerActivityDestination(activity: placement.opinion.activity)
                    } label: {
                        bubble(placement.opinion)
                    }
                    .buttonStyle(.plain)
                    .frame(width: policy.footprint.width, height: policy.footprint.height)
                    .contentShape(Rectangle())
                    .position(x: placement.frame.midX, y: placement.frame.midY)
                    .accessibilityLabel("\(placement.opinion.activity.actorName), \(placement.opinion.rankLabel), \(placement.opinion.activity.title)")
                    .accessibilityIdentifier("ticker.chart.opinion.\(placement.id)")
                }
            }
        }
    }

    private func bubble(_ opinion: TickerChartOpinion) -> some View {
        VStack(spacing: 2) {
            TickerActivityAvatar(activity: opinion.activity, size: policy.avatarSize)
                .overlay { Circle().stroke(opinion.activity.direction.color, lineWidth: 2) }
                .shadow(color: BSmartColor.chartMarkerShadow, radius: 3, y: 2)
            Text(opinion.rankLabel)
                .font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(BSmartColor.primaryText)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(BSmartColor.ink, in: Capsule())
        }
    }
}

struct TickerActivityDestination: View {
    let activity: TickerSmartActivityItem
    var body: some View {
        switch activity.payload {
        case let .account(update): SmartAccountEvidenceDetailView(update: update)
        case let .money(movement): SmartMoneyMovementDetailView(movement: movement)
        }
    }
}

struct TickerChartActivityList: View {
    let activities: [TickerSmartActivityItem]
    let symbol: String
    let range: HyperliquidChartRange
    var body: some View {
        ScrollView {
            TickerSmartActivityFeed(activities: activities, framed: false).padding(16)
        }
        .background(BSmartColor.ink)
        .navigationTitle("\(symbol) · \(range.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
    }
}
