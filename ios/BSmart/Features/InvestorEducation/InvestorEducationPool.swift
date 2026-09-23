import SwiftUI

struct InvestorEducationPool: View, Animatable {
    let platform: InvestorEducationSnapshot.Platform
    let tiles: [Int: Image]
    var progress: Double = 0
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let authors = platform.authors.filter { tiles[$0.tile] != nil }
            let count = authors.count
            guard count > 0 else { return }
            let columns = max(1, Int(ceil(sqrt(Double(count) * size.width / max(size.height, 1)))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let selected = authors.filter { $0.rank > 0 && $0.rank <= platform.selectedCount }
            let focusColumns = max(1, Int(ceil(sqrt(Double(selected.count) * size.width / max(size.height, 1)))))
            let focusRows = max(1, Int(ceil(Double(selected.count) / Double(focusColumns))))
            let selectedIDs = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($1.id, $0) })
            let amount = CGFloat(progress)
            func paint(_ index: Int) {
                let author = authors[index]
                let position = index
                let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
                var center = CGPoint(x: (CGFloat(position % columns) + 0.5) * cell.width,
                                     y: (CGFloat(position / columns) + 0.5) * cell.height)
                var diameter = min(cell.width, cell.height) * 0.82
                var layer = context
                if let focus = selectedIDs[author.id] {
                    let focusCell = CGSize(width: size.width / CGFloat(focusColumns), height: size.height / CGFloat(focusRows))
                    let target = CGPoint(x: (CGFloat(focus % focusColumns) + 0.5) * focusCell.width,
                                         y: (CGFloat(focus / focusColumns) + 0.5) * focusCell.height)
                    center.x += (target.x - center.x) * amount
                    center.y += (target.y - center.y) * amount
                    diameter += (min(focusCell.width, focusCell.height) * 0.72 - diameter) * amount
                } else { layer.opacity = 1 - progress * 0.94 }
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                layer.clip(to: Path(ellipseIn: rect))
                if let image = tiles[author.tile] { layer.draw(image, in: rect) }
                if selectedIDs[author.id] != nil && progress > 0.1 {
                    context.stroke(Path(ellipseIn: rect), with: .color(BSmartColor.brand.opacity(progress)), lineWidth: 1.5)
                }
            }
            for index in 0..<count where selectedIDs[authors[index].id] == nil { paint(index) }
            for index in 0..<count where selectedIDs[authors[index].id] != nil { paint(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(platform.name) · " + "%d real investor portraits".bSmartLocalized(platform.authors.count))
    }
}
