import SwiftUI

enum BSmartFloatingNavigationLayout {
    static func bottomSpacing(viewport: CGRect, navigationFrame: CGRect) -> CGFloat {
        guard !navigationFrame.isNull else { return 128 }
        return max(0, viewport.maxY - navigationFrame.minY) + 16
    }
}

private struct BSmartFloatingNavigationFrameKey: EnvironmentKey {
    static let defaultValue = CGRect.null
}

extension EnvironmentValues {
    var bSmartFloatingNavigationFrame: CGRect {
        get { self[BSmartFloatingNavigationFrameKey.self] }
        set { self[BSmartFloatingNavigationFrameKey.self] = newValue }
    }
}
