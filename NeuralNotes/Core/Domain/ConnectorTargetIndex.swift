import Foundation

/// Cached for one gesture. Large objects use a short overflow list rather than
/// populating thousands of cells. Returned IDs are sorted in visual hit order.
public struct ConnectorTargetIndex: Sendable {
    private struct Cell: Hashable, Sendable { var x: Int, y: Int }
    private var cells: [Cell: [UUID]] = [:]
    private var large: [UUID] = []
    private var boxes: [UUID: SnapRect] = [:]
    private var order: [UUID: Int] = [:]
    public init(boxes: [UUID: SnapRect], order: [UUID]) {
        self.order = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { _, last in last })
        for (id, box) in boxes where box.valid {
            self.boxes[id] = box
            let x0 = Int(floor(box.x / 64)), x1 = Int(floor(box.maxX / 64))
            let y0 = Int(floor(box.y / 64)), y1 = Int(floor(box.maxY / 64))
            if (x1 - x0 + 1) * (y1 - y0 + 1) > 256 { large.append(id); continue }
            for x in x0...x1 { for y in y0...y1 { cells[Cell(x: x, y: y), default: []].append(id) } }
        }
    }
    public func candidates(at point: StrokeSample, zoom: Double) -> [UUID] {
        guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000, zoom.isFinite else { return [] }
        let radius = 12 / max(0.05, zoom)
        let x0 = Int(floor((point.x - radius) / 64)), x1 = Int(floor((point.x + radius) / 64))
        let y0 = Int(floor((point.y - radius) / 64)), y1 = Int(floor((point.y + radius) / 64))
        var result = Set(large)
        for x in x0...x1 { for y in y0...y1 { result.formUnion(cells[Cell(x: x, y: y)] ?? []) } }
        return result.filter { id in
            guard let box = boxes[id] else { return false }
            return point.x >= box.x - radius && point.x <= box.maxX + radius && point.y >= box.y - radius && point.y <= box.maxY + radius
        }.sorted {
            let a = order[$0] ?? -1, b = order[$1] ?? -1
            return a == b ? $0.uuidString < $1.uuidString : a > b
        }
    }
}
