import Foundation
import WalletCore

struct CCTPForwardLog: Codable, Equatable, Sendable {
    let index: UInt64
    let address: String
    let topics: [String]
    let data: Data

    func validate() throws {
        guard FundingHex.decode(address)?.count == 20, (1...4).contains(topics.count),
              topics.allSatisfy({ FundingHex.decode($0)?.count == 32 }),
              data.startIndex == 0, data.count <= 2_048 else { throw FundingObservationError.invalidEvidence }
    }
}

struct CCTPForwardResolution: Equatable, Sendable {
    let destinationDex: UInt32
    let coreAmount: FundingQuantity
    let accountFee: FundingQuantity
}

// Event evidence is not a HyperCore ledger entry. Amounts here describe the EVM forwarding request.
enum CCTPForwardEventCodec {
    static let received = topic("MessageReceived(address,uint32,bytes32,bytes32,uint32,bytes)")
    static let forwarded = topic("MintAndForward(address,address,address,uint32,uint256)")
    static let transfer = topic("Transfer(address,address,uint256)")
    static let sent = topic("SendAsset(address,uint64,uint32)")
    static let feeApplied = topic("NewCoreAccountFeeApplied(address,uint64,uint256,uint64)")

    static func relevant(_ log: CCTPForwardLog) -> Bool {
        switch log.address {
        case CCTPArbitrumRoute.messageTransmitter: log.topics.first == received
        case CCTPArbitrumRoute.forwarderAddress: log.topics.first == forwarded
        case CCTPArbitrumRoute.destinationUSDC: log.topics.first == transfer
        case CCTPArbitrumRoute.coreDepositWallet: [transfer, sent, feeApplied].contains(log.topics.first ?? "")
        default: false
        }
    }

    static func resolve(_ logs: [CCTPForwardLog], proof: CCTPAttestedMessage,
                        intent: FundingJournalIntent) throws -> CCTPForwardResolution {
        guard (4...6).contains(logs.count), proof.message.startIndex == 0, proof.message.count == 432 else {
            throw FundingObservationError.invalidEvidence
        }
        for (offset, log) in logs.enumerated() {
            try log.validate()
            guard relevant(log), offset == 0 || logs[offset - 1].index < log.index else {
                throw FundingObservationError.invalidEvidence
            }
        }
        let owner = try CCTPSourceReadCodec.addressWord(intent.owner)
        let forwarder = try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.forwarderAddress)
        let wallet = try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.coreDepositWallet)
        let token = try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.destinationUSDC)
        let system = try CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.coreTokenSystemAddress)
        let net = try FundingQuantity(intent.amountUnits).subtracting(proof.fee)
        guard net > FundingQuantity(0) else { throw FundingObservationError.invalidEvidence }
        let scaled = try net.multiplied(by: FundingQuantity(100))
        _ = try scaled.uint64Checked()
        let message = logs[0]
        let footer = logs[logs.count - 1]
        let finality = FundingQuantity(UInt64(proof.message[144..<148].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }))
        let body = Data(proof.message[148...])
        let receivedData = try words([FundingQuantity(3).abi,
            CCTPSourceReadCodec.addressWord(CCTPArbitrumRoute.tokenMessenger), FundingQuantity(96).abi,
            FundingQuantity(UInt64(body.count)).abi]) + body + Data(repeating: 0, count: 4)
        guard message.address == CCTPArbitrumRoute.messageTransmitter,
              message.topics == [received, forwarder, try proof.nonce, finality.abi], message.data == receivedData,
              footer.address == CCTPArbitrumRoute.forwarderAddress,
              footer.topics == [forwarded, owner, wallet, token],
              footer.data == (try words([FundingQuantity(0).abi, net.abi])) else {
            throw FundingObservationError.invalidEvidence
        }
        let deposit = logs[1]
        guard deposit.address == CCTPArbitrumRoute.destinationUSDC,
              deposit.topics == [transfer, forwarder, wallet], deposit.data == (try words([net.abi])) else {
            throw FundingObservationError.invalidEvidence
        }
        let coreTransfer = logs[2]
        guard coreTransfer.address == CCTPArbitrumRoute.coreDepositWallet,
              coreTransfer.data == (try words([net.abi])) else { throw FundingObservationError.invalidEvidence }
        if logs.count == 4 {
            // Disabled DEX forwarding falls back to the recipient's spot account, even when the hook requested DEX 0.
            guard coreTransfer.topics == [transfer, owner, system] else { throw FundingObservationError.invalidEvidence }
            return .init(destinationDex: UInt32.max, coreAmount: scaled, accountFee: FundingQuantity(0))
        }
        guard coreTransfer.topics == [transfer, wallet, system] else { throw FundingObservationError.invalidEvidence }
        let send = logs[logs.count - 2]
        guard send.address == CCTPArbitrumRoute.coreDepositWallet, send.topics == [sent, owner], send.data.count == 64,
              try word(send.data, 1) == FundingQuantity(0) else { throw FundingObservationError.invalidEvidence }
        let amount = try word(send.data, 0)
        _ = try amount.uint64Checked()
        guard amount > FundingQuantity(0), amount <= scaled else { throw FundingObservationError.invalidEvidence }
        let fee = try scaled.subtracting(amount)
        if logs.count == 6 {
            let applied = logs[3]
            guard fee > FundingQuantity(0), applied.address == CCTPArbitrumRoute.coreDepositWallet,
                  applied.topics == [feeApplied, owner], applied.data == (try words([fee.abi, net.abi, amount.abi])) else {
                throw FundingObservationError.invalidEvidence
            }
        } else if fee != FundingQuantity(0) { throw FundingObservationError.invalidEvidence }
        return .init(destinationDex: 0, coreAmount: amount, accountFee: fee)
    }

    private static func topic(_ value: String) -> String { FundingHex.encode(Hash.keccak256(data: Data(value.utf8))) }
    private static func words(_ values: [String]) throws -> Data {
        try values.reduce(into: Data()) { data, value in
            guard let word = FundingHex.decode(value), word.count == 32 else { throw FundingObservationError.invalidEvidence }
            data.append(word)
        }
    }
    private static func word(_ data: Data, _ index: Int) throws -> FundingQuantity {
        guard data.startIndex == 0, data.count >= (index + 1) * 32 else { throw FundingObservationError.invalidEvidence }
        return try FundingQuantity(abi: FundingHex.encode(Data(data[(index * 32)..<((index + 1) * 32)])))
    }
}
