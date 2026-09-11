import SwiftUI

struct TodayInvestorDiscoveryWork: View {
    let highlight: TodayInvestorDiscoveryHighlight
    var onReceiptVisibilityChange: (Bool) -> Void = { _ in }
    @State private var showsReceipt = false

    var body: some View {
        if let intro = highlight.intro {
            Button { showsReceipt = true } label: {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        BSmartAssetMark(ticker: intro.ticker, size: 14)
                            .accessibilityIdentifier("discovery.work.logo.\(intro.ticker)")
                        Text(intro.ticker).fontWeight(.semibold)
                        Text("Representative work".bSmartLocalized)
                            .foregroundStyle(BSmartColor.secondaryText)
                        Spacer(minLength: 4)
                        if let value = highlight.stockReturn, let days = highlight.tradingSessions {
                            Text("%dD stock %@".bSmartLocalized(days,
                                value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%"))
                                .foregroundStyle(value >= 0 ? BSmartColor.bull : BSmartColor.bear)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 11)).frame(height: 15)
                    HStack(spacing: 4) {
                        if let first = highlight.firstOpinion {
                            Text("Earliest scored %@ · %@".bSmartLocalized(first.direction.label.bSmartLocalized, day(first.publishedAt)))
                            Spacer(minLength: 4)
                            Text(first.referencePrice.map { "Ref. %@".bSmartLocalized(price($0)) }
                                 ?? "Reference price unavailable".bSmartLocalized)
                        } else {
                            Text("View %@ · %@".bSmartLocalized(intro.direction.label.bSmartLocalized, day(intro.publishedAt)))
                            Spacer(minLength: 0)
                        }
                    }
                    .font(.system(size: 10)).foregroundStyle(BSmartColor.secondaryText).frame(height: 12)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(BSmartColor.primaryText)
                .frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discovery.highlight")
            .sheet(isPresented: $showsReceipt) {
                NavigationStack {
                    ScrollView {
                      VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            BSmartAssetMark(ticker: intro.ticker, size: 32)
                            Text(intro.ticker).font(.title2.bold())
                        }
                        if let first = highlight.firstOpinion {
                            LabeledContent("Earliest positive-contribution view".bSmartLocalized, value: first.direction.label.bSmartLocalized)
                            LabeledContent("Published (New York)".bSmartLocalized, value: timestamp(first.publishedAt))
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("discovery.receipt.published")
                            if let value = first.referencePrice {
                                LabeledContent("Reference close".bSmartLocalized, value: price(value))
                                LabeledContent("Price date".bSmartLocalized, value: first.priceDay ?? "--")
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("discovery.receipt.price-date")
                            }
                            if let entry = intro.entryPrice, entry.isFinite, entry > 0 {
                                LabeledContent("Settlement entry".bSmartLocalized, value: price(entry))
                                LabeledContent("Settlement period".bSmartLocalized,
                                    value: "\(intro.entryDay ?? "--") → \(intro.exitDay ?? "--")")
                            }
                            Text("The earliest Score-positive view for this investor's highest-contributing ticker. Reference price is the last completed daily close before publication, not an execution price. Return uses this same view's settlement window.".bSmartLocalized)
                                .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                            if let url = first.evidenceURL {
                                Link("Open original source".bSmartLocalized, destination: url).tint(BSmartColor.brand)
                            }
                        }
                      }.padding(20)
                    }
                    .background(BSmartColor.ink)
                    .accessibilityIdentifier("discovery.receipt")
                    .navigationTitle("Representative work".bSmartLocalized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done".bSmartLocalized) { showsReceipt = false }
                    } }
                }
                .presentationDetents([.large])
            }
            .onChange(of: showsReceipt) { _, value in onReceiptVisibilityChange(value) }
            .onDisappear { onReceiptVisibilityChange(false) }
        }
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .standard,
            timeZone: TimeZone(identifier: "America/New_York")!))
    }

    private func price(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(2)))
    }
}
