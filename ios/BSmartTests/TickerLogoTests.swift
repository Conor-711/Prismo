import UIKit
import SwiftUI
import XCTest
@testable import BSmart

final class TickerLogoTests: XCTestCase {
    @MainActor
    func testEveryRegisteredLogoLoadsFromCompiledAssetCatalog() {
        XCTAssertGreaterThan(TickerLogoRegistry.symbols.count, 480)
        for symbol in TickerLogoRegistry.symbols.sorted() {
            let image = UIImage(named: "Ticker_\(symbol)")
            XCTAssertNotNil(image, "Missing compiled logo: \(symbol)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, symbol)
            XCTAssertGreaterThan(image?.size.height ?? 0, 0, symbol)
        }
    }

    func testSpecialMarketCodesHaveExplicitAssets() {
        for symbol in ["SKHX", "SKHY", "SMSN", "DRAM", "SPCX", "SNDK", "MU",
                       "DGXX", "MRLN", "UNITREE", "LYTE", "NCLD", "YMTC", "SHEIN"] {
            XCTAssertTrue(TickerLogoRegistry.symbols.contains(symbol), symbol)
        }
        XCTAssertFalse(TickerLogoRegistry.symbols.contains("MARKET"))
    }

    func testWhiteMonochromeLogoAdaptsWithoutTintingColoredBrands() {
        XCTAssertTrue(TickerLogoRegistry.templateSymbols.contains("AVAV"))
        for symbol in ["META", "NVDA", "TSLA", "NBIS"] {
            XCTAssertFalse(TickerLogoRegistry.templateSymbols.contains(symbol))
        }
    }

    @MainActor
    func testCryptoLogosAreBundledSeparatelyFromEquityLogos() {
        for symbol in ["BTC", "ETH", "NEAR", "SOL", "DOGE", "XRP", "LINK", "ADA", "DOT", "XLM",
                       "ZEC", "SUI", "XMR", "HYPE", "AVAX", "BNB", "KPEPE"] {
            let image = UIImage(named: "Crypto_\(symbol)")
            XCTAssertNotNil(image, "Missing crypto logo: \(symbol)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, symbol)
            XCTAssertNotEqual(image?.renderingMode, .alwaysTemplate, symbol)
        }
    }

    @MainActor
    func testDetailLogoSelectionUsesCryptoAssetsBeforeMarketLoads() {
        for symbol in ["BTC", "ETH", "NEAR", "HYPE", "SOL"] {
            XCTAssertTrue(BSmartAssetMark(ticker: symbol).usesCryptoLogo, symbol)
        }
        XCTAssertFalse(BSmartAssetMark(ticker: "NVDA").usesCryptoLogo)
        XCTAssertFalse(BSmartAssetMark(ticker: "AI", isCrypto: false).usesCryptoLogo)
        XCTAssertTrue(BSmartAssetMark(ticker: "AI", isCrypto: true).usesCryptoLogo)
    }

    @MainActor
    func testStockLogoBackgroundFillsCircularFrame() throws {
        let renderer = ImageRenderer(content:
            BSmartAssetMark(ticker: "SKHX", size: 64)
                .background(Color.black, in: Circle())
                .clipShape(Circle()))
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        for (x, y) in [(32, 1), (32, 62), (1, 32), (62, 32)] {
            let offset = (y * 64 + x) * 4
            for channel in 0..<4 {
                XCTAssertGreaterThan(pixels[offset + channel], 240,
                                     "White logo background must reach the circle edge at \(x),\(y)")
            }
        }
    }

    @MainActor
    func testOfficialCryptoPaletteSurvivesLightAndDarkMode() throws {
        for scheme in [ColorScheme.light, .dark] {
            for symbol in ["BTC", "HYPE", "SOL"] {
                let renderer = ImageRenderer(content:
                    BSmartAssetMark(ticker: symbol, size: 64, isCrypto: true)
                        .environment(\.colorScheme, scheme))
                let image = try XCTUnwrap(renderer.uiImage, symbol)
                let cgImage = try XCTUnwrap(image.cgImage, symbol)
                var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
                let context = try XCTUnwrap(CGContext(
                    data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
                var white = 0, orange = 0, mint = 0, purple = 0
                for offset in stride(from: 0, to: pixels.count, by: 4) {
                    let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
                    guard pixels[offset + 3] > 240 else { continue }
                    if r > 240 && g > 240 && b > 240 { white += 1 }
                    if r > 220 && (100...190).contains(g) && b < 70 { orange += 1 }
                    if r < 180 && g > 220 && b > 170 { mint += 1 }
                    if r > 100 && b > 170 && g < 170 { purple += 1 }
                }
                switch symbol {
                case "BTC":
                    XCTAssertGreaterThan(white, 100, "BTC must retain its white mark")
                    XCTAssertGreaterThan(orange, 100, "BTC must retain its orange background")
                case "HYPE": XCTAssertGreaterThan(mint, 100, "HYPE must not render as a placeholder")
                default: XCTAssertGreaterThan(purple, 10, "SOL must retain its multicolor gradient")
                }
            }
        }
    }
}
