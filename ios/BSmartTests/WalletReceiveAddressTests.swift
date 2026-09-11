import XCTest
import CoreImage
import UIKit
@testable import BSmart

final class WalletReceiveAddressTests: XCTestCase {
    func testRejectsZeroMalformedAndNoncanonicalAddressInput() throws {
        for value in ["", "0x" + String(repeating: "0", count: 40), "0x1234", "ethereum:0x1234@42161",
                      "0x" + String(repeating: "a", count: 39), "0x" + String(repeating: "g", count: 40),
                      "0x" + String(repeating: "A", count: 40),
                      "0x" + String(repeating: "1", count: 40) + "\n"] {
            XCTAssertThrowsError(try WalletReceiveAddress(owner: value), value)
        }
    }

    func testQRDecodesToExactChecksumAddressAtDifferentDisplayScales() throws {
        let address = try WalletReceiveAddress(owner: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf")
        let image = try XCTUnwrap(WalletReceiveQRCode.image(address: address))
        for scale: CGFloat in [1, 2, 3] {
            let format = UIGraphicsImageRendererFormat(); format.scale = scale
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: 224, height: 224), format: format).image { context in
                context.cgContext.interpolationQuality = .none
                UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: 224, height: 224))
            }
            XCTAssertEqual(try Self.decode(rendered), [address.value])
        }
    }

    static func decode(_ image: UIImage) throws -> [String] {
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode,
            context: CIContext(options: [.useSoftwareRenderer: true]),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let input = CIImage(cgImage: try XCTUnwrap(image.cgImage))
        return detector.features(in: input).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    @MainActor
    func testClipboardCopiesExactFullPublicAddress() throws {
        let name = UIPasteboard.Name("bsmart.receive.test." + UUID().uuidString)
        let pasteboard = try XCTUnwrap(UIPasteboard(name: name, create: true))
        defer { UIPasteboard.remove(withName: name) }
        let address = try WalletReceiveAddress(owner: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf")
        WalletReceiveClipboard.copy(address, to: pasteboard)
        XCTAssertEqual(pasteboard.string, address.value)
        XCTAssertEqual(pasteboard.numberOfItems, 1)
    }
}
