import SwiftUI
import UIKit
import XCTest
@testable import BSmart

@MainActor
final class BSmartAppearanceContrastTests: XCTestCase {
    private let surfaces: [(String, Color)] = [
        ("page", BSmartColor.ink), ("canvas", BSmartColor.canvas),
        ("card", BSmartColor.surface), ("elevated", BSmartColor.elevated),
        ("recessed", BSmartColor.recessed), ("chart", BSmartColor.chartSurface),
    ]
    private let accents: [(String, Color)] = [
        ("brand", BSmartColor.brand), ("bull", BSmartColor.bull),
        ("bear", BSmartColor.bear), ("pulse", BSmartColor.pulse),
        ("sky", BSmartColor.sky), ("gold", BSmartColor.gold),
        ("orange", BSmartColor.orange), ("violet", BSmartColor.violet),
        ("pink", BSmartColor.pink), ("cyan", BSmartColor.cyan),
        ("electric", BSmartColor.electric),
    ]

    func testLightTextRemainsReadableAcrossSurfaces() {
        let text: [(String, Color)] = [
            ("primary", BSmartColor.primaryText), ("secondary", BSmartColor.secondaryText),
            ("metadata", BSmartColor.tertiaryText),
        ]
        for contrast in [UIAccessibilityContrast.normal, .high] {
            for (surfaceName, surface) in surfaces {
                for (textName, foreground) in text {
                    assertContrast(foreground, on: surface, minimum: 4.5,
                                   name: "\(textName) on \(surfaceName)", accessibilityContrast: contrast)
                }
            }
        }
    }

    func testLightRankAndDirectionLabelsOnTintedBadges() {
        for (name, accent) in accents {
            for (surfaceName, surface) in surfaces {
                let base = rgba(surface)
                let badge = rgba(accent.opacity(0.12)).over(base)
                XCTAssertGreaterThanOrEqual(rgba(accent).over(badge).contrast(with: badge), 4.5,
                                            "\(name) badge on \(surfaceName)")
            }
        }
    }

    func testFilledControlsHaveReadableInkInBothModes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, fill) in accents where ["brand", "bull", "bear", "pulse"].contains(name) {
                assertContrast(BSmartColor.onAccent, on: fill, minimum: 4.5,
                               name: "filled \(name) \(style.rawValue)", style: style)
            }
        }
    }

    func testEditorialCardsKeepDarkInkOnPaleFills() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(BSmartColor.skyInk, on: BSmartColor.skyFill, minimum: 7,
                           name: "money title", style: style)
            assertContrast(BSmartColor.pulseInk, on: BSmartColor.pulseFill, minimum: 7,
                           name: "pulse editorial", style: style)
        }
        assertContrast(BSmartColor.skySecondaryInk, on: BSmartColor.skyFill,
                       minimum: 4.5, name: "money metadata")
        for fill in [BSmartColor.consensusSurface, BSmartColor.consensusAlternateSurface] {
            assertContrast(BSmartColor.pulseInk.opacity(0.6), on: fill,
                           minimum: 4.5, name: "consensus timestamp")
            assertContrast(BSmartColor.brand, on: fill, minimum: 4.5, name: "consensus rank")
        }
    }

    func testLightChartAndNavigationContrast() {
        for color in [BSmartColor.chartSecondaryText, BSmartColor.chartTertiaryText] {
            assertContrast(color, on: BSmartColor.chartSurface, minimum: 4.5, name: "chart labels")
        }
        assertContrast(BSmartColor.chartVerticalCrosshair, on: BSmartColor.chartSurface,
                       minimum: 3, name: "vertical crosshair")
        assertContrast(BSmartColor.chartHorizontalCrosshair, on: BSmartColor.chartSurface,
                       minimum: 3, name: "horizontal crosshair")
        assertContrast(BSmartColor.tabInactiveForeground, on: BSmartColor.tabBarBottom,
                       minimum: 4.5, name: "inactive navigation")
        assertContrast(BSmartColor.line, on: BSmartColor.surface, minimum: 1.5, name: "card boundary")
    }

    func testDarkPaletteRemainsUnchanged() {
        let expected: [(Color, [Double])] = [
            (BSmartColor.ink, [9, 11, 11]), (BSmartColor.surface, [18, 21, 20]),
            (BSmartColor.secondaryText, [171, 179, 188]), (BSmartColor.line, [38, 44, 42]),
            (BSmartColor.brand, [89, 224, 190]), (BSmartColor.bull, [0, 195, 77]),
            (BSmartColor.bear, [255, 79, 36]), (BSmartColor.pulse, [212, 255, 68]),
            (BSmartColor.skyFill, [104, 183, 255]), (BSmartColor.onAccent, [11, 16, 8]),
        ]
        for (color, components) in expected {
            let resolved = rgba(color, style: .dark)
            for (actual, expected) in zip([resolved.r, resolved.g, resolved.b], components) {
                XCTAssertEqual(actual * 255, expected, accuracy: 0.01)
            }
        }
    }

    private func assertContrast(_ foreground: Color, on background: Color, minimum: Double,
                                name: String, style: UIUserInterfaceStyle = .light,
                                accessibilityContrast: UIAccessibilityContrast = .normal,
                                file: StaticString = #filePath, line: UInt = #line) {
        let base = rgba(background, style: style, contrast: accessibilityContrast)
        let ink = rgba(foreground, style: style, contrast: accessibilityContrast).over(base)
        XCTAssertGreaterThanOrEqual(ink.contrast(with: base), minimum, name, file: file, line: line)
    }

    private func rgba(_ color: Color, style: UIUserInterfaceStyle = .light,
                      contrast: UIAccessibilityContrast = .normal) -> RGBA {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast),
        ])
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }

    private struct RGBA {
        let r: Double, g: Double, b: Double, a: Double

        func over(_ background: Self) -> Self {
            Self(r: r * a + background.r * (1 - a), g: g * a + background.g * (1 - a),
                 b: b * a + background.b * (1 - a), a: 1)
        }

        private var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        func contrast(with other: Self) -> Double {
            (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
        }
    }
}
