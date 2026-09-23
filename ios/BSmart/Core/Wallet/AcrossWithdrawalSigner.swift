import Foundation

struct AcrossSigningStep: Sendable {
    let stepID: String
    let ecosystem: String
    let typedJSON: String

    init?(json: [String: Any]) {
        guard let id = json["stepId"] as? String, !id.isEmpty,
              let ecosystem = json["ecosystem"] as? String,
              ["hypercore", "evm-gasless"].contains(ecosystem),
              let typed = json["typedData"] as? [String: Any],
              let domain = typed["domain"] as? [String: Any],
              (ecosystem != "evm-gasless" || (domain["chainId"] as? Int) == 999),
              typed["primaryType"] is String, typed["message"] is [String: Any],
              typed["types"] is [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: typed, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        stepID = id; self.ecosystem = ecosystem; typedJSON = text
    }
}

protocol AcrossWithdrawalSigning: Sendable {
    func signAcrossStep(_ step: AcrossSigningStep, lease: FundingSigningLease) async throws -> String
}
