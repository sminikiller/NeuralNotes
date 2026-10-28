import Foundation

/// Cached once at gesture start. Large pages only query adjacent spatial cells.
public struct ShapeConnectionIndex: Sendable {
    private struct Cell: Hashable, Sendable { var x: Int, y: Int }
    private var cells: [Cell: [StrokeSample]] = [:]
    public init(points: [StrokeSample] = []) {
        for point in points.prefix(100_000) where point.x.isFinite && point.y.isFinite && abs(point.x) < 1_000_000 && abs(point.y) < 1_000_000 {
            let key = Cell(x: Int(floor(point.x / 64)), y: Int(floor(point.y / 64)))
            cells[key, default: []].append(point)
        }
    }
    public func nearest(_ point: StrokeSample, zoom: Double, tolerance: Double = 6) -> StrokeSample? {
        guard point.x.isFinite, point.y.isFinite, abs(point.x) < 1_000_000, abs(point.y) < 1_000_000,
              zoom.isFinite, tolerance.isFinite else { return nil }
        let radius = max(0, min(256, tolerance / max(0.05, zoom)))
        let x0 = Int(floor((point.x - radius) / 64)), x1 = Int(floor((point.x + radius) / 64))
        let y0 = Int(floor((point.y - radius) / 64)), y1 = Int(floor((point.y + radius) / 64))
        var best: StrokeSample?, distance = radius + 0.00001
        for x in x0...x1 {
            for y in y0...y1 {
                for candidate in cells[Cell(x: x, y: y)] ?? [] {
                    let value = hypot(candidate.x - point.x, candidate.y - point.y)
                    if value <= radius && value < distance { best = candidate; distance = value }
                }
            }
        }
        return best
    }
}
