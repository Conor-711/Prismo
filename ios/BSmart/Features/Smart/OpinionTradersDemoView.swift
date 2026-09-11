import SwiftUI

struct OpinionTradersDemoView: View {
    let data: OpinionTraderDemoData
    let onRefresh: () -> Void
    @State private var expanded = false
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Demo data".bSmartLocalized, systemImage: "testtube.2")
                    .font(.caption.weight(.semibold)).foregroundStyle(BSmartColor.gold)
                    .accessibilityIdentifier("opinion.traders.demo.badge")
                Spacer()
                BSmartAssetMark(ticker: data.ticker, size: 20)
                Text(data.ticker).font(.caption.weight(.semibold))
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Retry".bSmartLocalized)
                    .accessibilityIdentifier("opinion.traders.demo.refresh")
            }
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill").foregroundStyle(BSmartColor.brand)
                    Text("%d people traded through this opinion".bSmartLocalized(data.totalTraders))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("opinion.traders.demo.count")
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("opinion.traders.expand")

            if expanded {
                ForEach(Array(data.traders.prefix(showAll ? 6 : 3))) { trader in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            avatar(trader, size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trader.nickname).font(.subheadline.weight(.semibold))
                                Text(trader.openedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                            }
                            Spacer(minLength: 8)
                            Text("\(trader.leverage)x " + (trader.side == .long ? "Long" : "Short").bSmartLocalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trader.side == .long ? BSmartColor.bull : BSmartColor.bear)
                        }
                        HStack(alignment: .top, spacing: 20) {
                            metric("Entry price", value: trader.entryPrice.bSmartMarketPrice)
                            Spacer(minLength: 0)
                            metric("Position value", value: trader.notionalUSD.formatted(.bSmartDollars), alignment: .trailing)
                        }
                        Divider().overlay(BSmartColor.line)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("opinion.traders.demo.row.\(trader.id)")
                }
                if !showAll {
                    Button("Load more".bSmartLocalized) { showAll = true }
                        .font(.subheadline.weight(.medium)).foregroundStyle(BSmartColor.brand)
                        .frame(minHeight: 44).accessibilityIdentifier("opinion.traders.demo.more")
                }
                Text("Some traders keep their profiles private.".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(data.traders.prefix(4))) { trader in
                        avatar(trader, size: 30).padding(.trailing, 5)
                    }
                    Spacer()
                }
                .accessibilityHidden(true)
            }
            Text("Sample people and positions. Not real executions.".bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(BSmartColor.line) }
        .accessibilityIdentifier("opinion.traders.demo")
    }

    private func avatar(_ trader: OpinionTraderDemoData.Trader, size: CGFloat) -> some View {
        Image(trader.avatarAsset).resizable().scaledToFill()
            .frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(BSmartColor.line, lineWidth: 1))
            .accessibilityLabel(trader.nickname)
    }

    private func metric(_ label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}
