import Foundation

enum CCTPMessageResult: Equatable, Sendable {
    case waiting
    case complete(CCTPAttestedMessage, forwardHash: String?)
}

protocol CCTPMessageProviding: Sendable {
    func message(transactionHash: String) async throws -> CCTPMessageResult
}

final class CCTPMessageClient: CCTPMessageProviding, @unchecked Sendable {
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false; config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: MessageNoRedirects(), delegateQueue: nil)
    }

    func message(transactionHash: String) async throws -> CCTPMessageResult {
        guard FundingHex.decode(transactionHash)?.count == 32 else { throw FundingObservationError.invalidEvidence }
        let url = URL(string: "https://iris-api.circle.com/v2/messages/3?transactionHash=" + transactionHash)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, [200, 404].contains(http.statusCode),
                  http.url == url, http.mimeType == "application/json", http.expectedContentLength <= 32_768 else {
                throw FundingObservationError.unavailable
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 32_768 else { throw FundingObservationError.invalidEvidence }
                data.append(byte)
            }
            try Task.checkCancellation()
            if http.statusCode == 404 {
                struct NotFound: Decodable { let code: Int; let message: String }
                let result = try JSONDecoder().decode(NotFound.self, from: data)
                guard result.code == 404, result.message == "Not found." else { throw FundingObservationError.invalidEvidence }
                return .waiting
            }
            return try Self.decode(data, transactionHash: transactionHash)
        } catch is CancellationError { throw CancellationError() }
        catch { throw FundingObservationError.unavailable }
    }

    static func decode(_ data: Data, transactionHash: String) throws -> CCTPMessageResult {
        struct Response: Decodable {
            struct Message: Decodable {
                let message: String?
                let attestation: String?
                let cctpVersion: Int
                let status: String
                let eventNonce: String?
                let forwardTxHash: String?
            }
            let sourceTxHash: String
            let messages: [Message]
        }
        guard data.count <= 32_768, FundingHex.decode(transactionHash)?.count == 32 else { throw FundingObservationError.invalidEvidence }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.sourceTxHash.lowercased() == transactionHash, result.messages.count == 1,
              let row = result.messages.first, row.cctpVersion == 2 else { throw FundingObservationError.invalidEvidence }
        if row.status == "pending_confirmations" {
            guard row.attestation == "PENDING", row.message == nil || row.message == "0x" else {
                throw FundingObservationError.invalidEvidence
            }
            return .waiting
        }
        guard row.status == "complete", let message = row.message.flatMap({ FundingHex.decode($0.lowercased()) }),
              message.count == 432, let signatures = row.attestation.flatMap({ FundingHex.decode($0.lowercased()) }),
              let nonce = row.eventNonce?.lowercased(),
              try nonceWord(nonce) == FundingHex.encode(Data(message[12..<44])) else {
            throw FundingObservationError.invalidEvidence
        }
        let proof = CCTPAttestedMessage(message: message, attestation: signatures)
        _ = try proof.signers()
        let forward = row.forwardTxHash?.lowercased()
        guard forward == nil || FundingHex.decode(forward!)?.count == 32 else { throw FundingObservationError.invalidEvidence }
        return .complete(proof, forwardHash: forward)
    }

    private static func nonceWord(_ nonce: String) throws -> String {
        if nonce.hasPrefix("0x") { return try FundingQuantity(abi: nonce).abi }
        return try FundingQuantity(decimal: nonce).abi
    }
}

private final class MessageNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
