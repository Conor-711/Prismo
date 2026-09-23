import XCTest
import SwiftUI
@testable import BSmart

final class OpinionPortraitLayoutTests: XCTestCase {
    @MainActor
    func testOpaqueLogosReachTheCircularEdgeWithoutAnAddedWhiteMount() throws {
        for scheme in [ColorScheme.dark, .light] {
            for ticker in ["NBIS", "SNDK"] {
                let renderer = ImageRenderer(content: OpinionAssetPortrait(ticker: ticker, size: 132)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                for point in [CGPoint(x: 66, y: 12), CGPoint(x: 12, y: 66),
                              CGPoint(x: 120, y: 66), CGPoint(x: 66, y: 120)] {
                    let color = try pixel(image, at: point)
                    if ticker == "NBIS" {
                        XCTAssertGreaterThan(color[0], 0.8)
                        XCTAssertGreaterThan(color[1], 0.9)
                        XCTAssertLessThan(color[2], 0.5, "NBIS must retain its green background, not a white mount")
                    } else {
                        XCTAssertGreaterThan(color[0], color[1] + 0.3, "SNDK must retain its red background")
                    }
                    XCTAssertGreaterThan(color[3], 0.95)
                }
            }
        }
    }

    @MainActor
    func testTransparentAndTemplateLogosRenderInBothAppearances() throws {
        for scheme in [ColorScheme.dark, .light] {
            for ticker in ["NVDA", "META", "PLTR", "AVAV"] {
                let renderer = ImageRenderer(content: OpinionAssetPortrait(ticker: ticker, size: 132)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                var colors: Set<String> = []
                for y in stride(from: 24, through: 108, by: 6) {
                    for x in stride(from: 24, through: 108, by: 6) {
                        let value = try pixel(image, at: CGPoint(x: x, y: y))
                        colors.insert(value.prefix(3).map { String(Int($0 * 10)) }.joined(separator: ":"))
                    }
                }
                XCTAssertGreaterThan(colors.count, 2, "\(ticker) must remain visible in \(scheme) mode")
            }
        }
    }

    private func pixel(_ image: CGImage, at point: CGPoint) throws -> [Double] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes.map { Double($0) / 255 }
    }

    func testCompactCompositionMatchesApprovedPrototype() {
        let rest = OpinionPortraitLayout(width: 390, offset: 0)
        XCTAssertEqual(rest.portrait.baseHeight, 205)
        XCTAssertEqual(rest.avatarFrame.width, 109.2, accuracy: 0.01)
        XCTAssertEqual(rest.assetFrame.width, 93.6, accuracy: 0.01)
        XCTAssertEqual(rest.avatarFrame.minX, 78)
        XCTAssertEqual(rest.assetFrame.minX, 175.5, accuracy: 0.01)
        XCTAssertEqual(rest.avatarFrame.minY, 61)
        XCTAssertEqual(rest.assetFrame.minY, 92)
    }

    func testPullStretchesBothMarksTogetherWithoutChangingReservedHeight() {
        let rest = OpinionPortraitLayout(width: 390, offset: 0)
        let pulled = OpinionPortraitLayout(width: 390, offset: 150)
        XCTAssertEqual(pulled.portrait.imageHeight - rest.portrait.imageHeight, 150)
        XCTAssertEqual(pulled.portrait.baseHeight, rest.portrait.baseHeight)
        XCTAssertEqual(pulled.avatarFrame.minY - rest.avatarFrame.minY, 75)
        XCTAssertEqual(pulled.assetFrame.minY - rest.assetFrame.minY, 75)
        XCTAssertGreaterThan(pulled.compositionScale, rest.compositionScale)
        XCTAssertFalse(pulled.portrait.isCollapsed)
    }

    func testCompleteCirclesFitAllWidthsAndKeepDiagonalOverlap() {
        for width in [320.0, 375, 390, 430, 768, 1024] {
            let layout = OpinionPortraitLayout(width: width, offset: 0)
            XCTAssertLessThanOrEqual(layout.contentWidth, min(width, 390))
            let canvas = CGRect(x: 0, y: 0, width: width, height: layout.portrait.baseHeight)
            for frame in [layout.avatarFrame, layout.assetFrame] {
                XCTAssertTrue(canvas.contains(frame))
                XCTAssertEqual(frame.width, frame.height)
            }
            XCTAssertGreaterThan(layout.assetFrame.midY, layout.avatarFrame.midY)
            XCTAssertGreaterThan(layout.assetFrame.midX, layout.avatarFrame.midX)
            XCTAssertLessThan(layout.assetFrame.width, layout.avatarFrame.width)
            let distance = hypot(layout.assetFrame.midX - layout.avatarFrame.midX,
                layout.assetFrame.midY - layout.avatarFrame.midY)
            let radii = (layout.avatarFrame.width + layout.assetFrame.width) / 2
            XCTAssertGreaterThan(distance, radii * 0.75)
            XCTAssertLessThan(distance, radii)
        }
    }

    func testZoomedCirclesRemainInsideExpandedCanvas() {
        for width in [320.0, 390, 430, 1024] {
            for pull in [0.0, 10, 30, 60, 150, 500] {
                let layout = OpinionPortraitLayout(width: width, offset: pull)
                let height = layout.portrait.imageHeight
                let anchor = CGPoint(x: width * 0.49, y: height * 0.60)
                let scale = layout.compositionScale
                let canvas = CGRect(x: 0, y: 0, width: width, height: height)
                for frame in [layout.avatarFrame, layout.assetFrame] {
                    let zoomed = CGRect(x: anchor.x + (frame.minX - anchor.x) * scale,
                        y: anchor.y + (frame.minY - anchor.y) * scale,
                        width: frame.width * scale, height: frame.height * scale)
                    XCTAssertTrue(canvas.contains(zoomed))
                }
            }
        }
    }

    func testUpScrollCollapsesWithoutShrinkingAndReleaseRestoresScale() {
        let scrolled = OpinionPortraitLayout(width: 390, offset: -250)
        XCTAssertTrue(scrolled.portrait.isCollapsed)
        XCTAssertEqual(scrolled.compositionScale, 1)
        XCTAssertEqual(scrolled.portrait.imageHeight, scrolled.portrait.baseHeight)
        XCTAssertEqual(OpinionPortraitLayout(width: 390, offset: 0).compositionScale, 1)
        XCTAssertEqual(OpinionPortraitLayout(width: 390, offset: .nan).compositionScale, 1)
        XCTAssertEqual(OpinionPortraitLayout(width: 390, offset: 10_000).compositionScale, 1.18)
    }

    func testAuthorHeaderRetainsOriginalSizingAndFade() {
        XCTAssertEqual(SmartAccountPortraitLayout(width: 320, offset: 0).baseHeight, 260)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 390, offset: 0).baseHeight, 304.2, accuracy: 0.01)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 1024, offset: 0).baseHeight, 340)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 390, offset: 50).titleOpacity, 0.5)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 390, offset: 150).titleOpacity, 0)
    }
}
