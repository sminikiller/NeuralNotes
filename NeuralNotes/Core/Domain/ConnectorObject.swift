import Foundation

/// Native clients supply measured text rectangles. All math stays in page points.
public struct ConnectorObject: Sendable {
    public var id: UUID
    public var rect: SnapRect
    public var rotation: Double
    public var shape: ShapeElement?
    public var locked: Bool
    public init(id: UUID, rect: SnapRect, rotation: Double = 0, shape: ShapeElement? = nil, locked: Bool = false) {
        self.id = id; self.rect = rect; self.rotation = rotation; self.shape = shape; self.locked = locked
    }
    public init(shape: ShapeElement, locked: Bool = false) {
        self.init(id: shape.id, rect: .init(x: shape.x, y: shape.y, width: shape.width, height: shape.height),
                  rotation: shape.rotation ?? 0, shape: shape, locked: locked)
    }
    public var outline: [StrokeSample] {
        if let shape { return ShapeGeometry.polylines(ShapeGeometry.path(for: shape)).first ?? [] }
        let r = rect
        let corners: [StrokeSample] = [.init(x: r.x, y: r.y), .init(x: r.maxX, y: r.y), .init(x: r.maxX, y: r.maxY),
                                       .init(x: r.x, y: r.maxY), .init(x: r.x, y: r.y)]
        return corners.map { rotate($0) }
    }
    public var bounds: SnapRect {
        let points = outline
        guard let first = points.first else { return rect }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for p in points { x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y) }
        return .init(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
    }
    public func rotate(_ p: StrokeSample, inverse: Bool = false) -> StrokeSample {
        let radians = rotation.truncatingRemainder(dividingBy: 360) * .pi / 180 * (inverse ? -1 : 1)
        let dx = p.x - rect.midX, dy = p.y - rect.midY
        return .init(x: rect.midX + dx * cos(radians) - dy * sin(radians), y: rect.midY + dx * sin(radians) + dy * cos(radians))
    }
    public func point(at anchor: ShapeEndpoint) -> StrokeSample {
        rotate(.init(x: rect.x + anchor.x * rect.width, y: rect.y + anchor.y * rect.height))
    }
    public func anchor(at point: StrokeSample) -> ShapeEndpoint {
        let p = rotate(point, inverse: true)
        return .init(x: min(1, max(0, (p.x - rect.x) / rect.width)), y: min(1, max(0, (p.y - rect.y) / rect.height)))
    }
    public var connectionPoints: [StrokeSample] {
        if let shape {
            let values = ShapeGeometry.connectionPoints(shape)
            if values.count == 4 || shape.kind.isOpen { return values }
            var unlocked = self; unlocked.locked = false
            let anchors: [ShapeEndpoint] = [.init(x: 0.5, y: 0), .init(x: 1, y: 0.5), .init(x: 0.5, y: 1), .init(x: 0, y: 0.5)]
            return anchors.map { anchor in
                let candidate = point(at: anchor)
                return unlocked.closest(candidate, zoom: 1, magnet: false)?.point ?? candidate
            }
        }
        let anchors: [ShapeEndpoint] = [.init(x: 0.5, y: 0), .init(x: 1, y: 0.5), .init(x: 0.5, y: 1), .init(x: 0, y: 0.5)]
        return anchors.map { point(at: $0) }
    }
    public func closest(_ point: StrokeSample, zoom: Double, magnet: Bool = true) -> ConnectorEnd? {
        guard !locked, rect.valid, rotation.isFinite, point.x.isFinite, point.y.isFinite, zoom.isFinite else { return nil }
        if magnet, let candidate = connectionPoints.min(by: { distance($0, point) < distance($1, point) }),
           distance(candidate, point) <= 10 / max(0.05, zoom) { return end(at: candidate) }
        let line = outline
        guard line.count > 1 else { return nil }
        var closest = line[0], minimum = Double.infinity
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], dx = b.x - a.x, dy = b.y - a.y
            let denominator = dx * dx + dy * dy
            let raw = denominator > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / denominator : 0
            let t = max(0, min(1, raw)), p = StrokeSample(x: a.x + t * dx, y: a.y + t * dy)
            let d = distance(p, point)
            if d < minimum { closest = p; minimum = d }
        }
        return end(at: closest)
    }
    public func end(at p: StrokeSample) -> ConnectorEnd {
        .init(objectID: id, anchor: anchor(at: p), x: p.x, y: p.y)
    }
    /// An outward normal to the nearest contour segment, also for rotated shapes.
    public func normal(at point: StrokeSample) -> StrokeSample {
        let line = outline
        guard line.count > 1 else { return .init(x: 1, y: 0) }
        var best = Double.infinity, vector = StrokeSample(x: 1, y: 0), area = 0.0
        for i in 1..<line.count { area += line[i - 1].x * line[i].y - line[i].x * line[i - 1].y }
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i], d = ShapeGeometry.segmentDistance(point, a, b)
            let length = hypot(b.x - a.x, b.y - a.y)
            if d < best, length > 0.00001 {
                let sign = area >= 0 ? 1.0 : -1.0
                vector = .init(x: sign * (b.y - a.y) / length, y: sign * (a.x - b.x) / length); best = d
            }
        }
        return vector
    }
    private func distance(_ a: StrokeSample, _ b: StrokeSample) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
