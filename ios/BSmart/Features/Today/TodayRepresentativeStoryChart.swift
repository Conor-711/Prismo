import SwiftUI
import Charts

struct TodayRepresentativeStoryChart<Marker: View>: View {
    let story: TodayRepresentativeStory
    let marker: (TodayRepresentativeStory.Call, Int) -> Marker
    private let data: TodayRepresentativeChartData?
    @ScaledMetric(relativeTo: .caption) private var annotationSize = 11.0

    init(story: TodayRepresentativeStory,
         @ViewBuilder marker: @escaping (TodayRepresentativeStory.Call, Int) -> Marker) {
        self.story = story
        self.marker = marker
        data = TodayRepresentativeChartData(story: story)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let data {
                    priceChart(data).accessibilityHidden(true)
                    GeometryReader { geometry in
                        // Pure local geometry: never feed Chart layout back into @State.
                        annotations(data, size: geometry.size)
                    }
                }
            }
            .frame(height: max(128, min(annotationSize / 11, 1.45) * 128))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discovery.story.chart")
        }
    }

    private func priceChart(_ data: TodayRepresentativeChartData) -> some View {
        let domain = data.priceDomain
        return Chart {
            RuleMark(y: .value("Price", domain.lowerBound + (domain.upperBound - domain.lowerBound) * 0.35))
                .foregroundStyle(BSmartColor.chartGrid).lineStyle(StrokeStyle(lineWidth: 0.5))
            RuleMark(y: .value("Price", domain.lowerBound + (domain.upperBound - domain.lowerBound) * 0.7))
                .foregroundStyle(BSmartColor.chartGrid).lineStyle(StrokeStyle(lineWidth: 0.5))
            ForEach(story.prices) { point in
                AreaMark(x: .value("Date", point.time), yStart: .value("Floor", domain.lowerBound),
                         yEnd: .value("Price", point.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(BSmartColor.brand.opacity(0.1))
                LineMark(x: .value("Date", point.time), y: .value("Price", point.value))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(BSmartColor.brand)
            }
            if let close = story.prices.first(where: { $0.day == story.peak.day }) {
                RuleMark(x: .value("Date", story.peak.time), yStart: .value("Close", close.value),
                         yEnd: .value("High", story.peak.value))
                    .foregroundStyle(BSmartColor.gold.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1))
            }
            PointMark(x: .value("Date", story.peak.time), y: .value("Price", story.peak.value))
                .symbol(.diamond).symbolSize(38).foregroundStyle(BSmartColor.gold)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartXScale(domain: data.timeDomain,
                     range: .plotDimension(startPadding: 14, endPadding: 14))
        .chartYScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
    }

    private func annotations(_ data: TodayRepresentativeChartData, size: CGSize) -> some View {
        let anchors = data.callPoints(in: size)
        let peak = data.point(time: story.peak.time, value: story.peak.value, in: size)
        let labels = TodayRepresentativeStoryAnnotations(first: anchors[0], peak: peak,
            size: size, scale: min(annotationSize / 11, 1.45))
        let positions = BSmartChartMarkerLayout.positions(anchors: anchors, size: size,
            avoiding: [labels.first, labels.peak])
        return ZStack(alignment: .topLeading) {
            ForEach(Array(data.calls.enumerated()), id: \.element.id) { index, call in
                Path { path in
                    path.move(to: anchors[index])
                    path.addLine(to: positions[index])
                }
                .stroke(BSmartColor.brand.opacity(0.6), lineWidth: 1)
                .allowsHitTesting(false).accessibilityHidden(true)
                Circle().fill(BSmartColor.brand).frame(width: 5, height: 5)
                    .position(anchors[index]).allowsHitTesting(false).accessibilityHidden(true)
                marker(call, index + 1).frame(width: 44, height: 44).position(positions[index])
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(TodayRepresentativeStoryCopy.chartPrice(story.anchor.price)).fontWeight(.semibold)
                Text(TodayRepresentativeStoryCopy.day(story.anchor.day)).foregroundStyle(BSmartColor.secondaryText)
            }
            .font(.system(size: annotationSize).monospacedDigit())
            .padding(.horizontal, 3).background(BSmartColor.elevated.opacity(0.95))
            .frame(width: labels.first.width, height: labels.first.height, alignment: .leading)
            .position(x: labels.first.midX, y: labels.first.midY)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("discovery.story.first-price")
            Text(TodayRepresentativeStoryCopy.chartPrice(story.peak.value))
                .font(.system(size: annotationSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(BSmartColor.gold)
                .padding(.horizontal, 3).background(BSmartColor.elevated.opacity(0.95))
                .frame(width: labels.peak.width, height: labels.peak.height)
                .position(x: labels.peak.midX, y: labels.peak.midY)
                .accessibilityLabel("High %@ · %@".bSmartLocalized(TodayRepresentativeStoryCopy.chartPrice(story.peak.value),
                    TodayRepresentativeStoryCopy.day(story.peak.day)))
                .accessibilityIdentifier("discovery.story.peak-price")
        }.frame(width: size.width, height: size.height)
    }
}

struct TodayRepresentativeStoryNode: View {
    let index: Int
    var body: some View {
        Text("\(index)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(BSmartColor.onAccent)
            .frame(width: 26, height: 26).background(BSmartColor.brand, in: Circle())
            .overlay { Circle().stroke(BSmartColor.elevated, lineWidth: 2) }
            .frame(width: 44, height: 44).contentShape(Circle())
    }
}
