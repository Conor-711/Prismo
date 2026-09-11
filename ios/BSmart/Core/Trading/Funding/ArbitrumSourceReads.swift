import Foundation

struct ArbitrumSourceReads {
    let fields: [(String, FundingRPCRequest)]
    static let contracts = [ArbitrumDepositPolicy.nativeUSDC, CCTPArbitrumRoute.extensionAddress,
        CCTPArbitrumRoute.tokenMessenger, CCTPArbitrumRoute.messageTransmitter, CCTPArbitrumRoute.tokenMinter]

    init(owner: String, block: ArbitrumFundingBlock) throws {
        let usdc = ArbitrumDepositPolicy.nativeUSDC
        let route = CCTPArbitrumRoute.self
        let ownerWord = try CCTPSourceReadCodec.addressWord(owner)
        let tokenWord = try CCTPSourceReadCodec.addressWord(usdc)
        let extensionWord = try CCTPSourceReadCodec.addressWord(route.extensionAddress)
        let messengerWord = try CCTPSourceReadCodec.addressWord(route.tokenMessenger)
        var fields: [(String, FundingRPCRequest)] = [
            ("eth", .init(.balance, [.string(owner), block.reference])),
            ("nonce", .init(.nonce, [.string(owner), block.reference])),
            ("ownerCode", .init(.code, [.string(owner), block.reference]))
        ]
        for address in Self.contracts {
            fields.append((address, .init(.code, [.string(address), block.reference])))
        }
        func add(_ key: String, _ address: String, _ function: String, _ words: [String] = []) throws {
            fields.append((key, try Self.call(address, function, words, block: block)))
        }
        try add("usdc", usdc, "balanceOf(address)", [ownerWord])
        try add("decimals", usdc, "decimals()")
        try add("usdcPaused", usdc, "paused()")
        try add("ownerBlocked", usdc, "isBlacklisted(address)", [ownerWord])
        try add("extensionBlocked", usdc, "isBlacklisted(address)", [extensionWord])
        try add("minterBlocked", usdc, "isBlacklisted(address)", [CCTPSourceReadCodec.addressWord(route.tokenMinter)])
        try add("allowance", usdc, "allowance(address,address)", [extensionWord, messengerWord])
        try add("token", route.extensionAddress, "token()")
        try add("messenger", route.extensionAddress, "tokenMessenger()")
        try add("transmitter", route.tokenMessenger, "localMessageTransmitter()")
        try add("minter", route.tokenMessenger, "localMinter()")
        try add("remoteMessenger", route.tokenMessenger, "remoteTokenMessengers(uint32)", [FundingQuantity(19).abi])
        try add("ownerDenied", route.tokenMessenger, "isDenylisted(address)", [ownerWord])
        try add("extensionDenied", route.tokenMessenger, "isDenylisted(address)", [extensionWord])
        try add("domain", route.messageTransmitter, "localDomain()")
        try add("transmitterPaused", route.messageTransmitter, "paused()")
        try add("minterPaused", route.tokenMinter, "paused()")
        try add("burnLimit", route.tokenMinter, "burnLimitsPerMessage(address)", [tokenWord])
        self.fields = fields
    }

    static func call(_ address: String, _ function: String, _ words: [String] = [], block: ArbitrumFundingBlock) throws -> FundingRPCRequest {
        .init(.call, [.object(["to": .string(address), "data": .string(try CCTPSourceReadCodec.call(function, words: words))]), block.reference])
    }

    func snapshot(_ results: [FundingRPCValue], wallet: DeviceWalletSummary,
                  block: ArbitrumFundingBlock, now: Date) throws -> ArbitrumWalletSnapshot {
        guard results.count == fields.count else { throw FundingPreflightError.invalidResponse }
        let values = Dictionary(uniqueKeysWithValues: zip(fields.map(\.0), results))
        func value(_ key: String) throws -> FundingRPCValue {
            guard let result = values[key] else { throw FundingPreflightError.invalidResponse }
            return result
        }
        func number(_ key: String) throws -> FundingQuantity { try FundingQuantity(abi: value(key).text()) }
        guard try value("ownerCode").text() == "0x" else { throw FundingPreflightError.unsupportedWallet }
        var codeHashes: [String: String] = [:]
        for address in Self.contracts { codeHashes[address] = try CCTPSourceReadCodec.codeHash(value(address)) }
        for (key, address) in [
            ("token", ArbitrumDepositPolicy.nativeUSDC), ("messenger", CCTPArbitrumRoute.tokenMessenger),
            ("transmitter", CCTPArbitrumRoute.messageTransmitter), ("minter", CCTPArbitrumRoute.tokenMinter),
            ("remoteMessenger", CCTPArbitrumRoute.tokenMessenger)
        ] {
            guard try value(key).text() == CCTPSourceReadCodec.addressWord(address) else { throw FundingPreflightError.routeChanged }
        }
        guard try number("decimals") == FundingQuantity(6), try number("domain") == FundingQuantity(3),
              try number("burnLimit") > FundingQuantity(0) else { throw FundingPreflightError.routeChanged }
        for key in ["usdcPaused", "transmitterPaused", "minterPaused", "ownerBlocked", "extensionBlocked", "minterBlocked",
                    "ownerDenied", "extensionDenied"] {
            guard try !CCTPSourceReadCodec.boolean(value(key)) else { throw FundingPreflightError.transferRestricted }
        }
        return try .init(accountID: wallet.accountID, owner: wallet.address, block: block,
            usdc: number("usdc"), eth: FundingQuantity(rpc: value("eth").text()),
            nonce: FundingQuantity(rpc: value("nonce").text()), extensionAllowance: number("allowance"),
            burnLimit: number("burnLimit"), observedCodeHashes: codeHashes, checkedAt: now)
    }
}
