import Foundation
import WalletCore

struct CCTPAttestedMessage: Codable, Equatable, Sendable {
    let message: Data
    let attestation: Data

    var nonce: String { get throws { try word(at: 12).abi } }
    var fee: FundingQuantity { get throws { try word(at: 312) } }
    var expiration: UInt64 { get throws { try word(at: 344).uint64Checked() } }

    func validate(source: Data, intent: FundingJournalIntent) throws {
        try CCTPSourceMessage.validate(source, intent: intent)
        guard message.startIndex == 0, message.count == 432 else { throw FundingObservationError.invalidEvidence }
        var normalized = message
        for range in [12..<44, 144..<148, 312..<344, 344..<376] {
            normalized.replaceSubrange(range, with: Data(repeating: 0, count: range.count))
        }
        let finality = message[144..<148].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard normalized == source, message[12..<44].contains(where: { $0 != 0 }),
              finality == 1000 || finality == 2000,
              try fee <= FundingQuantity(intent.maximumCCTPFeeUnits), try fee < FundingQuantity(intent.amountUnits),
              try finality != 1000 || expiration > 0 else { throw FundingObservationError.invalidEvidence }
        _ = try expiration
        _ = try signers()
    }

    func signers() throws -> [String] {
        guard message.startIndex == 0, message.count == 432, attestation.startIndex == 0,
              attestation.count > 0, attestation.count <= 16 * 65,
              attestation.count.isMultiple(of: 65) else { throw FundingObservationError.invalidEvidence }
        let digest = Hash.keccak256(data: message)
        var result: [String] = []
        for offset in stride(from: 0, to: attestation.count, by: 65) {
            let signature = try FundingEthereumSignature(Data(attestation[offset..<offset + 65]), encoding: .legacy)
            let key = try signature.recover(digest: digest)
            let address = AnyAddress(publicKey: key, coin: .ethereum).description.lowercased()
            guard result.last.map({ $0 < address }) ?? true else { throw FundingObservationError.invalidEvidence }
            result.append(address)
        }
        return result
    }

    private func word(at offset: Int) throws -> FundingQuantity {
        guard message.startIndex == 0, message.count == 432 else { throw FundingObservationError.invalidEvidence }
        return try FundingQuantity(abi: FundingHex.encode(Data(message[offset..<offset + 32])))
    }
}
