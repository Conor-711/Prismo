import Foundation
import WalletCore

// Encodes a fixed, self-submitted route only. No key access, signing, or broadcast.
enum CCTPDepositCodec {
    static let functionType = "batchDepositForBurnWithAuth((uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32),(uint256,uint32,bytes32,bytes32,uint256,uint32,bytes))"

    static func authorizationJSON(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, now: Date) throws -> String {
        try plan.validate(wallet: wallet, now: now)
        let payload: [String: Any] = [
            "types": [
                "EIP712Domain": fields([("name", "string"), ("version", "string"),
                    ("chainId", "uint256"), ("verifyingContract", "address")]),
                "ReceiveWithAuthorization": fields([("from", "address"), ("to", "address"),
                    ("value", "uint256"), ("validAfter", "uint256"), ("validBefore", "uint256"), ("nonce", "bytes32")])
            ],
            "primaryType": "ReceiveWithAuthorization",
            "domain": ["name": "USD Coin", "version": "2", "chainId": ArbitrumDepositPolicy.chainID,
                       "verifyingContract": ArbitrumDepositPolicy.nativeUSDC] as [String: Any],
            "message": ["from": plan.owner, "to": CCTPArbitrumRoute.extensionAddress,
                        "value": String(plan.quote.amountUnits), "validAfter": String(plan.validAfter),
                        "validBefore": String(plan.validBefore), "nonce": FundingHex.encode(plan.authorizationNonce)]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw CCTPFundingError.invalidPlan }
        return json
    }

    static func callData(plan: CCTPDepositPlan, wallet: DeviceWalletSummary, authorization: String, now: Date) throws -> Data {
        let typedJSON = try authorizationJSON(plan: plan, wallet: wallet, now: now)
        guard authorization.utf8.count == 132, let authorizationBytes = FundingHex.decode(authorization) else {
            throw CCTPFundingError.invalidPlan
        }
        let signature = try FundingEthereumSignature(authorizationBytes, encoding: .legacy)
        let digest = EthereumAbi.encodeTyped(messageJson: typedJSON)
        _ = try signature.recover(digest: digest, owner: plan.owner)
        let recipient = Data(repeating: 0, count: 12) + FundingHex.decode(CCTPArbitrumRoute.forwarderAddress)!
        let auth = tuple([
            uint(plan.quote.amountUnits), uint(plan.validAfter), uint(plan.validBefore),
            bytes(plan.authorizationNonce, fixed: true), uint(UInt64(signature.parity + 27), bits: 8),
            bytes(signature.r, fixed: true), bytes(signature.s, fixed: true)
        ])
        let burn = tuple([
            uint(plan.quote.amountUnits), uint(UInt64(CCTPArbitrumRoute.destinationDomain), bits: 32),
            bytes(recipient, fixed: true), bytes(recipient, fixed: true), uint(plan.quote.maximumFeeUnits),
            uint(UInt64(CCTPArbitrumRoute.finalityThreshold), bits: 32), bytes(plan.hookData, fixed: false)
        ])
        var input = EthereumAbiFunctionEncodingInput()
        input.functionName = "batchDepositForBurnWithAuth"
        input.tokens = [auth, burn]
        let encoded = EthereumAbi.encodeFunction(coin: .ethereum, input: try input.serializedData())
        let output = try EthereumAbiFunctionEncodingOutput(serializedBytes: encoded)
        guard output.error == .ok, output.functionType == functionType, output.encoded.count == 580 else {
            throw CCTPFundingError.invalidPlan
        }
        return output.encoded
    }

    private static func fields(_ items: [(String, String)]) -> [[String: String]] {
        items.map { ["name": $0.0, "type": $0.1] }
    }

    private static func uint(_ value: UInt64, bits: UInt32 = 256) -> EthereumAbiToken {
        var number = EthereumAbiNumberNParam()
        number.bits = bits
        var bigEndian = value.bigEndian
        number.value = withUnsafeBytes(of: &bigEndian) { Data($0) }
        var token = EthereumAbiToken()
        token.numberUint = number
        return token
    }

    private static func bytes(_ value: Data, fixed: Bool) -> EthereumAbiToken {
        var token = EthereumAbiToken()
        if fixed { token.byteArrayFix = value } else { token.byteArray = value }
        return token
    }

    private static func tuple(_ tokens: [EthereumAbiToken]) -> EthereumAbiToken {
        var value = EthereumAbiTupleParam()
        value.params = tokens
        var token = EthereumAbiToken()
        token.tuple = value
        return token
    }
}
