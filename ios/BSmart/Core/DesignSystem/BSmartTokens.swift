import SwiftUI

enum BSmartColor {
    static let ink = adaptive(dark: (9, 11, 11), light: (245, 247, 246))
    static let canvas = adaptive(dark: (6, 8, 8), light: (238, 242, 240))
    static let surface = adaptive(dark: (18, 21, 20), light: (255, 255, 255))
    static let elevated = adaptive(dark: (24, 28, 27), light: (255, 255, 255))
    static let recessed = adaptive(dark: (13, 16, 15), light: (240, 244, 242))
    static let tabBarTop = adaptive(dark: (31, 32, 38), light: (233, 236, 235))
    static let tabBarBottom = adaptive(dark: (20, 21, 26), light: (219, 224, 222))
    static let tabSelectionTop = adaptive(dark: (61, 62, 70), light: (255, 255, 255))
    static let tabSelectionBottom = adaptive(dark: (40, 41, 48), light: (236, 240, 238))
    static let tabSelectedForeground = adaptive(dark: (255, 255, 255), light: (20, 27, 24))
    static let tabBarOutline = adaptiveAlpha(
        dark: (255, 255, 255, 0.15),
        light: (62, 76, 70, 0.18)
    )
    static let tabSelectionOutline = adaptiveAlpha(
        dark: (255, 255, 255, 0.17),
        light: (62, 76, 70, 0.14)
    )
    static let line = adaptive(dark: (38, 44, 42), light: (218, 225, 222))
    static let strongLine = adaptive(dark: (58, 68, 64), light: (190, 201, 196))
    static let primaryText = adaptive(dark: (247, 248, 249), light: (20, 27, 24))
    static let secondaryText = adaptive(dark: (171, 179, 188), light: (76, 88, 83))
    static let tertiaryText = adaptive(dark: (107, 116, 126), light: (113, 126, 120))
    static let brand = adaptive(dark: (89, 224, 190), light: (0, 128, 101))
    static let pulse = adaptive(dark: (212, 255, 68), light: (91, 126, 0))
    static let pulseFill = adaptive(dark: (212, 255, 68), light: (205, 244, 72))
    static let pulseInk = Color(red: 11 / 255, green: 16 / 255, blue: 8 / 255)
    static let electric = adaptive(dark: (92, 118, 255), light: (52, 78, 200))
    static let sky = adaptive(dark: (104, 183, 255), light: (0, 103, 174))
    static let bear = adaptive(dark: (255, 92, 108), light: (194, 37, 58))
    static let gold = adaptive(dark: (255, 202, 75), light: (145, 94, 0))
    static let orange = adaptive(dark: (255, 145, 92), light: (174, 73, 18))
    static let violet = adaptive(dark: (174, 125, 255), light: (105, 64, 180))
    static let pink = adaptive(dark: (236, 112, 188), light: (174, 48, 125))
    static let cyan = adaptive(dark: (80, 215, 230), light: (0, 119, 134))
    static let floatingShadow = adaptiveAlpha(
        dark: (0, 0, 0, 0.38),
        light: (22, 38, 32, 0.14)
    )
    static let compactShadow = adaptiveAlpha(
        dark: (0, 0, 0, 0.34),
        light: (22, 38, 32, 0.1)
    )

    // Charts use their own semantic roles because their dense controls and labels
    // need stronger local contrast than ordinary cards in both appearances.
    static let chartSurface = adaptive(dark: (18, 31, 32), light: (248, 251, 250))
    static let chartPrimaryText = adaptive(dark: (255, 255, 255), light: (20, 27, 24))
    static let chartSelectedControlForeground = adaptive(dark: (18, 31, 32), light: (255, 255, 255))
    static let chartSecondaryText = adaptiveAlpha(
        dark: (255, 255, 255, 0.62),
        light: (50, 64, 58, 0.76)
    )
    static let chartTertiaryText = adaptiveAlpha(
        dark: (255, 255, 255, 0.48),
        light: (65, 80, 73, 0.66)
    )
    static let chartGrid = adaptiveAlpha(
        dark: (255, 255, 255, 0.09),
        light: (38, 54, 47, 0.13)
    )
    static let chartControl = adaptiveAlpha(
        dark: (255, 255, 255, 0.08),
        light: (38, 54, 47, 0.07)
    )
    static let chartPlot = adaptiveAlpha(
        dark: (255, 255, 255, 0.018),
        light: (38, 54, 47, 0.025)
    )
    static let chartWatermark = adaptiveAlpha(
        dark: (255, 255, 255, 0.055),
        light: (38, 54, 47, 0.055)
    )
    static let chartMarkerShadow = adaptiveAlpha(
        dark: (0, 0, 0, 0.42),
        light: (22, 38, 32, 0.18)
    )

    private static func adaptive(
        dark: (Double, Double, Double),
        light: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.0 / 255,
                green: components.1 / 255,
                blue: components.2 / 255,
                alpha: 1
            )
        })
    }

    private static func adaptiveAlpha(
        dark: (Double, Double, Double, Double),
        light: (Double, Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.0 / 255,
                green: components.1 / 255,
                blue: components.2 / 255,
                alpha: components.3
            )
        })
    }
}

enum BSmartSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
    static let xxxLarge: CGFloat = 40
}

enum BSmartRadius {
    static let control: CGFloat = 4
    static let card: CGFloat = 8
}

enum BSmartMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let standard = Animation.easeInOut(duration: 0.22)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)
}

extension View {
    func bSmartSurface(padding: CGFloat = BSmartSpacing.large) -> some View {
        self
            .padding(padding)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.5)
            }
    }

    func bSmartPage() -> some View {
        self
            .foregroundStyle(BSmartColor.primaryText)
            .background(BSmartColor.ink.ignoresSafeArea())
            .tint(BSmartColor.brand)
    }

    func bSmartDetailPage() -> some View {
        modifier(BSmartDetailPageModifier())
    }

    @ViewBuilder
    func bSmartMatchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func bSmartZoomNavigationTransition<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    func bSmartPanel(
        padding: CGFloat = BSmartSpacing.medium,
        fill: Color = BSmartColor.surface,
        border: Color = BSmartColor.line
    ) -> some View {
        self
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(border, lineWidth: 0.6)
            }
    }
}

private struct BSmartDetailPageModifier: ViewModifier {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var visibilityToken = UUID()

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismissDetail) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Back".bSmartLocalized)
                    .accessibilityIdentifier("detail.back")
                }
            }
            .onAppear {
                router.setTabBarHidden(true, token: visibilityToken)
            }
            .onDisappear {
                router.setTabBarHidden(false, token: visibilityToken)
            }
    }

    private func dismissDetail() {
        router.setTabBarHidden(false, token: visibilityToken)
        DispatchQueue.main.async {
            dismiss()
        }
    }
}

struct BSmartDetailNavigationLink<ID: Hashable, Destination: View, Label: View>: View {
    let id: ID
    private let destination: () -> Destination
    private let label: () -> Label
    @Namespace private var transition

    init(
        id: ID,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.id = id
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
                .bSmartZoomNavigationTransition(sourceID: id, in: transition)
        } label: {
            label()
                .bSmartMatchedTransitionSource(id: id, in: transition)
        }
    }
}
