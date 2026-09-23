import SwiftUI

enum BSmartColor {
    static let ink = adaptive(dark: (9, 11, 11), light: (246, 247, 249))
    static let canvas = adaptive(dark: (6, 8, 8), light: (235, 239, 243))
    static let surface = adaptive(dark: (18, 21, 20), light: (255, 255, 255))
    static let elevated = adaptive(dark: (24, 28, 27), light: (237, 242, 246))
    static let recessed = adaptive(dark: (13, 16, 15), light: (233, 238, 241))
    static let tabBarTop = adaptive(dark: (31, 32, 38), light: (255, 255, 255))
    static let tabBarBottom = adaptive(dark: (20, 21, 26), light: (248, 250, 252))
    static let tabSelectionTop = adaptive(dark: (61, 62, 70), light: (223, 241, 234))
    static let tabSelectionBottom = adaptive(dark: (40, 41, 48), light: (213, 235, 226))
    static let tabSelectedForeground = adaptive(dark: (255, 255, 255), light: (0, 93, 72))
    static let tabInactiveForeground = adaptiveAlpha(dark: (171, 179, 188, 0.74), light: (68, 81, 94, 1))
    static let tabBarOutline = adaptiveAlpha(
        dark: (255, 255, 255, 0.15),
        light: (60, 80, 97, 0.2)
    )
    static let tabSelectionOutline = adaptiveAlpha(
        dark: (255, 255, 255, 0.17),
        light: (0, 106, 85, 0.3)
    )
    static let line = adaptive(dark: (38, 44, 42), light: (190, 201, 210))
    static let strongLine = adaptive(dark: (58, 68, 64), light: (145, 160, 173))
    static let primaryText = adaptive(dark: (247, 248, 249), light: (19, 27, 35))
    static let secondaryText = adaptive(dark: (171, 179, 188), light: (62, 76, 89))
    static let tertiaryText = adaptive(dark: (107, 116, 126), light: (81, 97, 110))
    static let brand = adaptive(dark: (89, 224, 190), light: (0, 106, 85))
    static let bull = adaptive(dark: (0, 195, 77), light: (0, 109, 47))
    static let pulse = adaptive(dark: (212, 255, 68), light: (74, 102, 0))
    static let pulseFill = adaptive(dark: (212, 255, 68), light: (205, 244, 72))
    static let pulseInk = Color(red: 11 / 255, green: 16 / 255, blue: 8 / 255)
    // Saturated controls use white ink in light mode; pale editorial fills keep dark ink.
    static let onAccent = adaptive(dark: (11, 16, 8), light: (255, 255, 255))
    static let skyFill = adaptive(dark: (104, 183, 255), light: (207, 230, 251))
    static let skyInk = Color(red: 7 / 255, green: 20 / 255, blue: 33 / 255)
    static let skySecondaryInk = adaptiveAlpha(dark: (7, 20, 33, 0.56), light: (7, 20, 33, 0.76))
    static let consensusSurface = adaptive(dark: (233, 238, 235), light: (255, 255, 255))
    static let consensusAlternateSurface = adaptive(dark: (219, 229, 241), light: (231, 240, 252))
    static let tintedCardBase = adaptiveAlpha(dark: (0, 0, 0, 0), light: (255, 255, 255, 1))
    static let electric = adaptive(dark: (92, 118, 255), light: (52, 78, 200))
    static let sky = adaptive(dark: (104, 183, 255), light: (0, 96, 163))
    static let bear = adaptive(dark: (255, 79, 36), light: (179, 43, 12))
    static let gold = adaptive(dark: (255, 202, 75), light: (130, 83, 0))
    static let orange = adaptive(dark: (255, 145, 92), light: (156, 63, 13))
    static let violet = adaptive(dark: (174, 125, 255), light: (105, 64, 180))
    static let pink = adaptive(dark: (236, 112, 188), light: (163, 42, 115))
    static let cyan = adaptive(dark: (80, 215, 230), light: (0, 105, 119))
    static let floatingShadow = adaptiveAlpha(
        dark: (0, 0, 0, 0.38),
        light: (22, 38, 32, 0.14)
    )
    static let compactShadow = adaptiveAlpha(
        dark: (0, 0, 0, 0.34),
        light: (22, 38, 32, 0.1)
    )

    // Raised content, inset controls and disabled actions have distinct light-mode roles.
    static let raisedSurface = adaptive(dark: (24, 28, 27), light: (255, 255, 255))
    static let selectedControlSurface = adaptive(dark: (24, 28, 27), light: (255, 255, 255))
    static let disabledControl = adaptive(dark: (13, 16, 15), light: (225, 232, 238))
    static let inputOutline = adaptiveAlpha(dark: (0, 0, 0, 0), light: (121, 137, 151, 1))
    static let softDivider = adaptiveAlpha(dark: (38, 44, 42, 0.5), light: (190, 201, 210, 1))
    static let cardShadow = adaptiveAlpha(dark: (0, 0, 0, 0), light: (27, 43, 58, 0.045))
    static let controlOutline = adaptiveAlpha(dark: (255, 255, 255, 0.16), light: (19, 27, 35, 0.12))
    static let tradeBarSurface = adaptiveAlpha(dark: (0, 0, 0, 0.82), light: (255, 255, 255, 1))
    static let tradeBarText = adaptiveAlpha(dark: (255, 255, 255, 0.88), light: (62, 76, 89, 1))
    static let tradeBarLine = adaptiveAlpha(dark: (255, 255, 255, 0.11), light: (190, 201, 210, 1))

    // Charts use their own semantic roles because their dense controls and labels
    // need stronger local contrast than ordinary cards in both appearances.
    static let chartSurface = adaptive(dark: (18, 31, 32), light: (255, 255, 255))
    static let chartPrimaryText = adaptive(dark: (255, 255, 255), light: (20, 27, 24))
    static let chartSelectedControlForeground = adaptive(dark: (18, 31, 32), light: (255, 255, 255))
    static let chartSecondaryText = adaptiveAlpha(
        dark: (255, 255, 255, 0.62),
        light: (68, 81, 94, 1)
    )
    static let chartTertiaryText = adaptiveAlpha(
        dark: (255, 255, 255, 0.48),
        light: (81, 97, 110, 1)
    )
    static let chartGrid = adaptiveAlpha(
        dark: (255, 255, 255, 0.09),
        light: (75, 92, 107, 0.24)
    )
    static let chartControl = adaptiveAlpha(
        dark: (255, 255, 255, 0.08),
        light: (38, 54, 47, 0.09)
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
    static let chartAxisGrid = adaptiveAlpha(dark: (38, 44, 42, 0.5), light: (190, 201, 210, 0.8))
    static let chartVerticalCrosshair = adaptiveAlpha(dark: (171, 179, 188, 0.6), light: (68, 81, 94, 0.8))
    static let chartHorizontalCrosshair = adaptiveAlpha(dark: (171, 179, 188, 0.4), light: (68, 81, 94, 0.65))

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
            .shadow(color: BSmartColor.cardShadow, radius: 5, y: 2)
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
        in namespace: Namespace.ID,
        enabled: Bool = true
    ) -> some View {
        if #available(iOS 18.0, *), enabled {
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
            .shadow(color: BSmartColor.cardShadow, radius: 5, y: 2)
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
            .background {
                BSmartDetailVisibilityObserver(router: router, token: visibilityToken)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
    private let usesZoomTransition: Bool
    private let destination: () -> Destination
    private let label: () -> Label
    @Namespace private var transition

    init(
        id: ID,
        usesZoomTransition: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.id = id
        self.usesZoomTransition = usesZoomTransition
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
                .bSmartZoomNavigationTransition(sourceID: id, in: transition, enabled: usesZoomTransition)
        } label: {
            label()
                .bSmartMatchedTransitionSource(id: id, in: transition)
        }
    }
}
