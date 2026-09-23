import XCTest
import PrivySDK
@testable import BSmart

final class EmbeddedWalletFailureTests: XCTestCase {
    func testNestedAuthenticationErrorsKeepTheirActionableCause() {
        let denied = ApiError.apiError(httpCode: 403, errorCode: "invalid_native_app_id", description: "private response")
        XCTAssertEqual(EmbeddedWalletFailure.map(.authenticationFailure(reason: .failureDuringAuthentication(error: denied)),
                                                stage: .authentication), .accessDenied)
        XCTAssertEqual(EmbeddedWalletFailure.map(ApiError.apiError(httpCode: 401, errorCode: "invalid_jwt", description: "secret"),
                                                stage: .authentication), .authenticationFailed)
    }

    func testNetworkTimeoutAndCreationHaveDifferentMessagesWithoutRawResponse() {
        XCTAssertEqual(EmbeddedWalletFailure.map(URLError(.notConnectedToInternet), stage: .restoring), .networkUnavailable)
        XCTAssertEqual(EmbeddedWalletFailure.map(URLError(.timedOut), stage: .signing), .timedOut)
        XCTAssertEqual(EmbeddedWalletFailure.map(.embeddedWalletFailure(reason: .creationFailed), stage: .creating), .creationFailed)
        XCTAssertEqual(EmbeddedWalletFailure.map(.initializationFailed, stage: .configuration), .notConfigured)
        XCTAssertEqual(EmbeddedWalletFailure.map(ApiError.apiError(httpCode: 503, errorCode: "unavailable", description: "secret"),
                                                stage: .restoring), .networkUnavailable)
    }

    func test429IsNotReportedAsGenericNetworkFailure() {
        let api = ApiError.apiError(httpCode: 429, errorCode: "rate_limit", description: "private")
        XCTAssertEqual(EmbeddedWalletFailure.map(api, stage: .restoring), .rateLimited(seconds: 60))
        XCTAssertEqual(EmbeddedWalletFailure.map(.authenticationFailure(reason: .failureDuringAuthentication(error: api)),
                                                stage: .authentication), .rateLimited(seconds: 60))
    }
}
