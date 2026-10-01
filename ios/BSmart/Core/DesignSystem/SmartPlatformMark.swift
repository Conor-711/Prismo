import SwiftUI

struct SmartPlatformMark: View {
    let platform: String
    var size: CGFloat = 16

    private var normalized: String { platform.lowercased() }
    private var isSubjectKind: Bool { ["congress", "celebrity", "institution"].contains(normalized) }
    private var subjectColor: Color {
        switch normalized {
        case "congress": Color(red: 0.78, green: 0.86, blue: 0.92)
        case "celebrity": Color(red: 0.95, green: 0.79, blue: 0.54)
        default: Color(red: 0.64, green: 0.85, blue: 0.78)
        }
    }

    var body: some View {
        Group {
            if normalized == "bsmart" {
                Image("PlatformBSmart")
                    .resizable()
                    .scaledToFit()
            } else if normalized == "congress" {
                WhiteHouseMark()
                    .fill(subjectColor)
                    .frame(width: size * 0.82, height: size * 0.7)
            } else if normalized == "celebrity" {
                NecktieMark()
                    .fill(subjectColor)
                    .frame(width: size * 0.55, height: size * 0.8)
            } else if normalized == "institution" {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(subjectColor)
            } else if normalized.contains("youtube") {
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
        .background(normalized == "bsmart" ? .white : isSubjectKind
                    ? Color(red: 0.08, green: 0.12, blue: 0.13) : BSmartColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay {
            if isSubjectKind {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(subjectColor.opacity(0.36), lineWidth: 0.75)
            }
        }
        .accessibilityLabel(isSubjectKind ? subjectAccessibilityLabel : platform)
    }

    private var subjectAccessibilityLabel: String {
        switch normalized {
        case "congress": return "Politician".bSmartLocalized
        case "celebrity": return "Public figure".bSmartLocalized
        default: return "Institution".bSmartLocalized
        }
    }
}

private struct WhiteHouseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            path.addRect(CGRect(x: rect.minX + x * w, y: rect.minY + y * h,
                                width: width * w, height: height * h))
        }
        path.move(to: CGPoint(x: rect.minX + 0.5 * w, y: rect.minY + 0.02 * h))
        path.addLine(to: CGPoint(x: rect.minX + 0.23 * w, y: rect.minY + 0.29 * h))
        path.addLine(to: CGPoint(x: rect.minX + 0.77 * w, y: rect.minY + 0.29 * h))
        path.closeSubpath()
        box(0.27, 0.31, 0.46, 0.09)
        for x in [0.31, 0.43, 0.55, 0.67] { box(x, 0.42, 0.045, 0.39) }
        box(0.21, 0.81, 0.58, 0.08)
        box(0.03, 0.57, 0.19, 0.32)
        box(0.78, 0.57, 0.19, 0.32)
        box(0.02, 0.91, 0.96, 0.07)
        return path
    }
}

private struct NecktieMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        path.move(to: point(0.24, 0.04))
        for (x, y) in [(0.76, 0.04), (0.67, 0.3), (0.33, 0.3)] { path.addLine(to: point(x, y)) }
        path.closeSubpath()
        path.move(to: point(0.33, 0.35))
        for (x, y) in [(0.67, 0.35), (0.81, 0.85), (0.5, 0.99), (0.19, 0.85)] {
            path.addLine(to: point(x, y))
        }
        path.closeSubpath()
        return path
    }
}
