import SwiftUI

struct SmartPlatformMark: View {
    let platform: String
    var size: CGFloat = 16

    private var normalized: String { platform.lowercased() }

    var body: some View {
        Group {
            if normalized.contains("youtube") {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(Color.red)
            } else if normalized.contains("reddit") {
                Image("PlatformReddit")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else if normalized.contains("xueqiu") || normalized.contains("雪球") {
                Text("雪")
                    .font(.system(size: size * 0.62, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized.contains("toss") {
                Text("T")
                    .font(.system(size: size * 0.68, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized.contains("hyper") {
                Text("H")
                    .font(.system(size: size * 0.66, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized == "x" || normalized.contains("twitter") {
                Text("X")
                    .font(.system(size: size * 0.7, weight: .black))
                    .foregroundStyle(BSmartColor.primaryText)
            } else {
                Image(systemName: "network")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .background(BSmartColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityLabel(platform)
    }
}
