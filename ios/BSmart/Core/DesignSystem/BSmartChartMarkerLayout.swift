import CoreGraphics

enum BSmartChartMarkerLayout {
    static func positions(anchors: [CGPoint], size: CGSize, avoiding: [CGRect] = []) -> [CGPoint] {
        var placed: [CGPoint] = []
        for anchor in anchors {
            var candidates: [CGPoint] = []
            for dy in [-32.0, 32, -78, 78, -124, 124] {
                for dx in [0.0, -48, 48, -96, 96] {
                    candidates.append(CGPoint(x: min(max(anchor.x + dx, 22), max(22, size.width - 22)),
                                              y: min(max(anchor.y + dy, 22), max(22, size.height - 22))))
                }
            }
            if !avoiding.isEmpty {
                // A dense early cluster may need the free area beyond the nearby offsets.
                var grid: [CGPoint] = []
                for y in stride(from: 22.0, through: max(22, size.height - 22), by: 22) {
                    for x in stride(from: 22.0, through: max(22, size.width - 22), by: 22) {
                        grid.append(CGPoint(x: x, y: y))
                    }
                }
                candidates += grid.sorted { hypot($0.x - anchor.x, $0.y - anchor.y) < hypot($1.x - anchor.x, $1.y - anchor.y) }
            }
            let point = candidates.first { candidate in
                placed.allSatisfy { hypot($0.x - candidate.x, $0.y - candidate.y) >= 46 }
                    && avoiding.allSatisfy { !$0.intersects(CGRect(x: candidate.x - 22, y: candidate.y - 22, width: 44, height: 44)) }
            } ?? candidates[0]
            placed.append(point)
        }
        return placed
    }
}
