import SwiftUI
import XCTest
@testable import BSmart

@MainActor
final class AccountProviderButtonTests: XCTestCase {
    func testBothTitlesFollowAppLanguage() {
        let original = BSmartLocalization.language
        defer { BSmartLocalization.configure(original) }
        BSmartLocalization.configure(.english)
        XCTAssertEqual(AccountProviderButtonContent.title(for: .apple), "Continue with Apple")
        XCTAssertEqual(AccountProviderButtonContent.title(for: .google), "Continue with Google")
        BSmartLocalization.configure(.simplifiedChinese)
        XCTAssertEqual(AccountProviderButtonContent.title(for: .apple), "使用 Apple 继续")
        XCTAssertEqual(AccountProviderButtonContent.title(for: .google), "使用 Google 继续")
    }

    func testEqualButtonHeightAcrossLanguagesThemesAndTextSizes() {
        let original = BSmartLocalization.language
        defer { BSmartLocalization.configure(original) }
        for language in [AppLanguage.english, .simplifiedChinese] {
            BSmartLocalization.configure(language)
            for scheme in [ColorScheme.light, .dark] {
                for textSize in [DynamicTypeSize.large, .accessibility2] {
                    let heights = AccountIdentityProvider.allCases.map { provider in
                        let view = AccountProviderButton(provider: provider, action: {})
                            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, textSize)
                        let host = UIHostingController(rootView: view)
                        return host.sizeThatFits(in: CGSize(width: 330, height: 400)).height
                    }
                    XCTAssertEqual(heights[0], heights[1], accuracy: 1)
                    XCTAssertGreaterThanOrEqual(heights[0], 56)
                    XCTAssertLessThan(heights[0], 200)
                }
            }
        }
    }
}
