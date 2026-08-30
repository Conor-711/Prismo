import SwiftUI

private enum SignalLibrarySection: String, CaseIterable {
    case saved = "Saved"
    case ignored = "Ignored"
}

struct SignalLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: SignalLibrarySection = .saved

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Signal collection", selection: $section) {
                    ForEach(SignalLibrarySection.allCases, id: \.self) { item in
                        Text(item.rawValue.bSmartLocalized).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(BSmartSpacing.large)

                Group {
                    switch section {
                    case .saved:
                        savedContent
                    case .ignored:
                        ignoredContent
                    }
                }
            }
            .background(BSmartColor.ink)
            .navigationTitle("Signal library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .bSmartPage()
    }

    @ViewBuilder
    private var savedContent: some View {
        if model.savedSignals.isEmpty {
            emptyState(
                title: "No saved signals",
                detail: "Save a signal from its detail page to keep the evidence close.",
                symbol: "bookmark"
            )
        } else {
            signalList(model.savedSignals, allowsRestore: false)
        }
    }

    @ViewBuilder
    private var ignoredContent: some View {
        if model.ignoredPortfolioSignals.isEmpty {
            emptyState(
                title: "No ignored signals",
                detail: "Signals you remove from Today can be restored here.",
                symbol: "eye.slash"
            )
        } else {
            signalList(model.ignoredPortfolioSignals, allowsRestore: true)
        }
    }

    private func signalList(
        _ signals: [PortfolioSignal],
        allowsRestore: Bool
    ) -> some View {
        List(signals) { signal in
            Group {
                if allowsRestore {
                    HStack(spacing: BSmartSpacing.medium) {
                        signalRow(signal)
                        Button("Restore") {
                            model.restoreIgnoredSignal(signal.id)
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                    }
                } else {
                    BSmartDetailNavigationLink(id: "signal-library-\(signal.id)") {
                        EventDetailView(signal: signal)
                    } label: {
                        signalRow(signal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(BSmartColor.surface)
            .listRowSeparatorTint(BSmartColor.line)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func signalRow(_ signal: PortfolioSignal) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: signal.ticker, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.ticker)
                    .font(.subheadline.weight(.bold))
                Text(signal.title.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: BSmartSpacing.small)
        }
        .contentShape(Rectangle())
    }

    private func emptyState(title: String, detail: String, symbol: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
