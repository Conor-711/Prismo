import SwiftUI

struct AddPositionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let position: PortfolioPosition?
    private let isTickerLocked: Bool

    @State private var kind: PortfolioEntryKind
    @State private var ticker: String
    @State private var companyName: String
    @State private var shares: String
    @State private var averageCost: String
    @State private var portfolioWeight: String

    init(
        position: PortfolioPosition? = nil,
        prefilledTicker: String = "",
        prefilledCompanyName: String = "",
        initialKind: PortfolioEntryKind = .position
    ) {
        self.position = position
        self.isTickerLocked = position != nil || !prefilledTicker.isEmpty
        _kind = State(initialValue: position?.resolvedKind ?? initialKind)
        _ticker = State(initialValue: position?.ticker ?? prefilledTicker)
        _companyName = State(initialValue: position?.companyName ?? prefilledCompanyName)
        _shares = State(initialValue: Self.inputValue(position?.shares))
        _averageCost = State(initialValue: Self.inputValue(position?.averageCost))
        _portfolioWeight = State(initialValue: Self.inputValue(position?.portfolioWeight.map { $0 * 100 }))
    }

    private var parsedShares: Double? { optionalNumber(shares) }
    private var parsedCost: Double? { optionalNumber(averageCost) }
    private var parsedWeight: Double? { optionalNumber(portfolioWeight) }

    private var canSave: Bool {
        guard !ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard validOptionalNumber(shares, range: 0...Double.greatestFiniteMagnitude) else { return false }
        guard validOptionalNumber(averageCost, range: 0...Double.greatestFiniteMagnitude) else { return false }
        guard validOptionalNumber(portfolioWeight, range: 0...100) else { return false }
        return kind == .watchlist || (parsedShares ?? 0) > 0 || (parsedWeight ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    Picker("Tracking type", selection: $kind) {
                        ForEach(PortfolioEntryKind.allCases, id: \.self) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    field(
                        title: "Ticker",
                        placeholder: "NVDA",
                        text: $ticker,
                        keyboard: .default,
                        capitalization: .characters
                    )
                    .disabled(isTickerLocked)
                    .opacity(isTickerLocked ? 0.72 : 1)

                    field(
                        title: "Company",
                        placeholder: "Optional",
                        text: $companyName,
                        keyboard: .default
                    )

                    if kind == .position {
                        Divider().overlay(BSmartColor.line)

                        field(
                            title: "Shares",
                            placeholder: "Optional",
                            text: $shares,
                            keyboard: .decimalPad
                        )
                        field(
                            title: "Average cost",
                            placeholder: "Optional",
                            text: $averageCost,
                            keyboard: .decimalPad,
                            prefix: "$"
                        )
                        field(
                            title: "Portfolio weight",
                            placeholder: "Optional",
                            text: $portfolioWeight,
                            keyboard: .decimalPad,
                            suffix: "%"
                        )
                    }
                }
                .padding(BSmartSpacing.xLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BSmartColor.ink)
            .navigationTitle(position == nil ? "Add ticker" : "Edit \(position?.ticker ?? "ticker")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(position == nil ? "Add" : "Save") {
                        let didSave = model.savePortfolioEntry(
                            id: position?.id,
                            ticker: ticker,
                            companyName: companyName,
                            kind: kind,
                            shares: parsedShares,
                            averageCost: parsedCost,
                            portfolioWeight: parsedWeight.map { $0 / 100 }
                        )
                        if didSave { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("position-editor.screen")
        .bSmartPage()
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        capitalization: TextInputAutocapitalization = .never,
        prefix: String? = nil,
        suffix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)

            HStack(spacing: BSmartSpacing.small) {
                if let prefix {
                    Text(prefix)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .foregroundStyle(BSmartColor.primaryText)
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
            .padding(.horizontal, BSmartSpacing.medium)
            .frame(height: 48)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 1)
            }
        }
    }

    private func optionalNumber(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private func validOptionalNumber(_ value: String, range: ClosedRange<Double>) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        guard let number = Double(normalized) else { return false }
        return range.contains(number)
    }

    private static func inputValue(_ value: Double?) -> String {
        guard let value, value != 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
    }
}
