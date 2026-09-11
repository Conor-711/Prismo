import XCTest
@testable import BSmart

final class AccountDeletionClientTests: XCTestCase {
    private let ticket = AccountDeletionTicket(id: UUID(), statusToken: String(repeating: "disposable-ticket_", count: 4))
    private let accountToken = String(repeating: "disposable-account_", count: 4)

    func testDeletionAcceptanceUsesAccountTokenAndExactConfirmedBody() async throws {
        let client = makeClient()
        AccountExchangeURLProtocol.configure(status: 202, data: try response())
        let receipt = try await client.requestAccountDeletion(confirmed(), accountToken: accountToken)
        XCTAssertEqual(receipt.id, ticket.id)
        XCTAssertEqual(receipt.status, .pending)
        let (request, data) = try XCTUnwrap(AccountExchangeURLProtocol.captured)
        XCTAssertEqual(request.url?.absoluteString, "https://account.example.invalid/v1/auth/account/deletions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accountToken)")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Secret"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["id", "statusToken", "confirmDeletion", "walletRecoveryConfirmed"])
        XCTAssertEqual(body["id"] as? String, ticket.id.uuidString)
        XCTAssertEqual(body["statusToken"] as? String, ticket.statusToken)
        XCTAssertEqual(body["confirmDeletion"] as? Bool, true)
        XCTAssertEqual(body["walletRecoveryConfirmed"] as? Bool, true)
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
    }

    func testRecoveryUsesOnlyInstallationBearerAndBodyTicketNotAccountCredentials() async throws {
        AccountExchangeURLProtocol.configure(data: try response(completed: true))
        let receipt = try await makeClient().accountDeletionStatus(ticket: ticket)
        XCTAssertEqual(receipt.status, .completed)
        XCTAssertEqual(receipt.retryAfterSeconds, 0)
        let (request, data) = try XCTUnwrap(AccountExchangeURLProtocol.captured)
        XCTAssertEqual(request.url?.absoluteString,
            "https://account.example.invalid/v1/auth/account/deletions/\(ticket.id.uuidString)/status")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer disposable-installation-token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.url!.absoluteString.contains(ticket.statusToken))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: String], ["statusToken": ticket.statusToken])
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
    }

    func testBothConfirmationsAreRequiredBeforeEncodingOrNetwork() async throws {
        let client = makeClient()
        for (confirmed, recovery) in [(false, false), (true, false), (false, true)] {
            let input = AccountDeletionRequest(ticket: ticket, confirmDeletion: confirmed, walletRecoveryConfirmed: recovery)
            AccountExchangeURLProtocol.configure(status: 202, data: try response())
            XCTAssertThrowsError(try JSONEncoder().encode(input))
            do { _ = try await client.requestAccountDeletion(input, accountToken: accountToken); XCTFail("Unconfirmed deletion sent") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .confirmationRequired) }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
        }
    }

    func testInvalidTicketsAndAccountTokensAreRejectedBeforeNetwork() async throws {
        let client = makeClient()
        for value in ["short", String(repeating: "x", count: 257), ticket.statusToken + "\n", ticket.statusToken + "\u{00e9}"] {
            let invalid = AccountDeletionTicket(id: ticket.id, statusToken: value)
            AccountExchangeURLProtocol.configure(status: 202, data: try response())
            do { _ = try await client.accountDeletionStatus(ticket: invalid); XCTFail("Invalid ticket sent") } catch {}
            do {
                _ = try await client.requestAccountDeletion(.init(ticket: invalid, confirmDeletion: true,
                                                                 walletRecoveryConfirmed: true), accountToken: accountToken)
                XCTFail("Invalid deletion sent")
            } catch {}
            do { _ = try await client.requestAccountDeletion(confirmed(), accountToken: value); XCTFail("Invalid account token sent") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .unauthorized) }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
        }
    }

    func testReauthenticationAndMissingTicketAreNotWalletRecoveryOrCompletion() async throws {
        let client = makeClient()
        for (status, expected) in [(401, AccountDeletionError.unauthorized), (404, .unavailable), (409, .reauthenticationRequired),
                                  (422, .invalidResponse), (429, .unavailable), (503, .unavailable)] {
            AccountExchangeURLProtocol.configure(status: status, data: Data(ticket.statusToken.utf8))
            do { _ = try await client.requestAccountDeletion(confirmed(), accountToken: accountToken); XCTFail("Error accepted") }
            catch {
                XCTAssertEqual(error as? AccountDeletionError, expected)
                XCTAssertFalse(String(reflecting: error).contains(ticket.statusToken))
            }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
        AccountExchangeURLProtocol.configure(status: 404, data: Data(ticket.statusToken.utf8))
        do { _ = try await client.accountDeletionStatus(ticket: ticket); XCTFail("Missing ticket completed") }
        catch { XCTAssertEqual(error as? AccountDeletionError, .requestNotFound) }
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
    }

    func testUnexpectedSuccessStatusOriginMimeOrOversizedBodyIsNotAccepted() async throws {
        let client = makeClient()
        for (status, mime, data, url) in [
            (200, "application/json", try response(), nil), (204, "application/json", Data(), nil),
            (302, "application/json", try response(), nil), (202, "text/html", try response(), nil),
            (202, "application/json", Data(repeating: 32, count: 65_537), nil),
            (202, "application/json", try response(), URL(string: "https://other.example.invalid/v1/auth/account/deletions"))
        ] {
            AccountExchangeURLProtocol.configure(status: status, mime: mime, data: data, url: url)
            do { _ = try await client.requestAccountDeletion(confirmed(), accountToken: accountToken); XCTFail("Bad response accepted") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .invalidResponse) }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
    }

    func testReceiptMustMatchExactTicketAndStateInvariants() async throws {
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: response()) as? [String: Any])
        let variants: [[String: Any]] = [
            ["id": UUID().uuidString], ["status": "deleted"], ["status": "completed"],
            ["completedAt": "2026-01-01T00:00:00Z"], ["retryAfterSeconds": 0],
            ["retryAfterSeconds": 3601], ["retryAfterSeconds": true], ["retryAfterSeconds": 30.5],
            ["requestedAt": "2099-01-01T00:00:00Z"], ["requestedAt": "invalid-private-\(ticket.statusToken)"],
            ["accessToken": ticket.statusToken], ["walletAddress": "untrusted"]
        ]
        let client = makeClient()
        for changes in variants {
            let data = try JSONSerialization.data(withJSONObject: base.merging(changes) { _, new in new })
            AccountExchangeURLProtocol.configure(data: data)
            do { _ = try await client.accountDeletionStatus(ticket: ticket); XCTFail("Invalid receipt accepted") }
            catch {
                XCTAssertEqual(error as? AccountDeletionError, .invalidResponse)
                XCTAssertFalse(String(reflecting: error).contains(ticket.statusToken))
            }
        }
        for key in base.keys {
            var missing = base
            missing.removeValue(forKey: key)
            AccountExchangeURLProtocol.configure(data: try JSONSerialization.data(withJSONObject: missing))
            do { _ = try await client.accountDeletionStatus(ticket: ticket); XCTFail("Missing required field accepted") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .invalidResponse) }
        }
    }

    func testCompletedReceiptRequiresChronologicalCompletionAndZeroRetry() async throws {
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: response(completed: true)) as? [String: Any])
        let variants: [[String: Any]] = [["completedAt": "2000-01-01T00:00:00Z"],
                                       ["completedAt": "2099-01-01T00:00:00Z"], ["retryAfterSeconds": 30]]
        for changes in variants {
            AccountExchangeURLProtocol.configure(data: try JSONSerialization.data(withJSONObject: base.merging(changes) { _, new in new }))
            do { _ = try await makeClient().accountDeletionStatus(ticket: ticket); XCTFail("Contradictory completion accepted") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .invalidResponse) }
        }
    }

    func testNoHttpsOrCancelledCallerCannotSendDeletion() async throws {
        AccountExchangeURLProtocol.configure(status: 202, data: try response())
        for url in ["http://account.example.invalid", "https://user:secret@account.example.invalid", "https://account.example.invalid?q=secret"] {
            do { _ = try await makeClient(url: url).requestAccountDeletion(confirmed(), accountToken: accountToken); XCTFail("Unsafe transport") }
            catch { XCTAssertEqual(error as? AccountDeletionError, .unavailable) }
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await makeClient().requestAccountDeletion(confirmed(), accountToken: accountToken)
        }
        do { _ = try await task.value; XCTFail("Cancelled deletion sent") } catch is CancellationError {} catch { XCTFail("Wrong error") }
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
    }

    func testFixtureAndRedactedRequestDiagnostics() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "account-deletion-status", withExtension: "json"))
        let receipt = try BSmartJSONCoding.makeDecoder().decode(AccountDeletionReceipt.self, from: Data(contentsOf: url))
        XCTAssertEqual(receipt.status, .pending)
        XCTAssertEqual(receipt.retryAfterSeconds, 30)
        XCTAssertNil(receipt.completedAt)
        for value in [String(describing: ticket), String(reflecting: ticket), String(describing: confirmed()), String(reflecting: confirmed())] {
            XCTAssertFalse(value.contains(ticket.statusToken))
            XCTAssertTrue(value.contains("redacted"))
        }
    }

    private func confirmed() -> AccountDeletionRequest {
        .init(ticket: ticket, confirmDeletion: true, walletRecoveryConfirmed: true)
    }

    private func makeClient(url: String = "https://account.example.invalid") -> HTTPAccountAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountExchangeURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "old-session", "Cookie": "private", "X-Secret": "private"]
        return .init(baseURL: URL(string: url)!, authorization: ExchangeInstallationAuthorization(), configuration: config)
    }

    private func response(completed: Bool = false) throws -> Data {
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
        return try JSONSerialization.data(withJSONObject: ["id": ticket.id.uuidString,
            "status": completed ? "completed" : "pending", "requestedAt": timestamp,
            "completedAt": completed ? timestamp as Any : NSNull(), "retryAfterSeconds": completed ? 0 : 30])
    }
}
