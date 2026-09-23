import SwiftUI

struct OpinionTradeSplitBar: View {
    let longTraders: Int
    let shortTraders: Int
    var compact = false

    private var fraction: Double {
        let total = Double(longTraders) + Double(shortTraders)
        return total > 0 ? Double(longTraders) / total : 0
    }

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            HStack {
                Text("Long · %d".bSmartLocalized(longTraders)).foregroundStyle(BSmartColor.bull)
                Spacer(minLength: 12)
                Text("Short · %d".bSmartLocalized(shortTraders)).foregroundStyle(BSmartColor.bear)
            }.font(.caption.weight(compact ? .medium : .semibold)).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(BSmartColor.recessed)
                    if longTraders > 0 || shortTraders > 0 {
                        Rectangle().fill(BSmartColor.bear)
                        Rectangle().fill(BSmartColor.bull).frame(width: geometry.size.width * fraction)
                    }
                }.clipShape(Capsule())
            }.frame(height: compact ? 3 : 7).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("opinion.traders.split")
    }
}
