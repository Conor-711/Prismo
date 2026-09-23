import SwiftUI

struct SmartMoneySourceActivity: View {
    let movements: [SmartMoneyMovement]
    @State private var expanded = false

    var body: some View {
        if !movements.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Account activity".bSmartLocalized).font(.title3.weight(.bold))
                ForEach(Array(movements.sorted { $0.observedAt > $1.observedAt }
                    .prefix(expanded ? movements.count : 5))) { movement in
                    BSmartDetailNavigationLink(id: "money-source-\(movement.id)") {
                        SmartMoneyMovementDetailView(movement: movement)
                    } label: {
                        HStack(spacing: 12) {
                            BSmartAssetMark(ticker: movement.ticker, size: 32)
                            Text(movement.ticker).font(.subheadline.weight(.semibold))
                            Text(movement.action.label).font(.subheadline)
                            Spacer()
                            Text(movement.direction.label.bSmartLocalized).foregroundStyle(movement.direction.color)
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().overlay(BSmartColor.line)
                }
                if movements.count > 5 {
                    Button((expanded ? "Show less" : "View all").bSmartLocalized) { expanded.toggle() }
                        .frame(minHeight: 44)
                }
            }
        }
    }
}
