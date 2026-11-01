import Foundation

public struct RulerGuide: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case ruler, square45, square60 }
    public var kind = Kind.ruler
    public var x: Double, y: Double, angle: Double
    public var length = 640.0
    public var thickness = 44.0
    public static let halfWidth = 22.0
    public init(x: Double = 384, y: Double = 512, angle: Double = 0) { self.x = x; self.y = y; self.angle = angle }
    public var vertices: [StrokeSample] {
        let height = kind == .square45 ? length : length / sqrt(3)
        let local: [StrokeSample] = kind == .ruler
            ? [.init(x: -length / 2, y: -thickness / 2), .init(x: length / 2, y: -thickness / 2),
               .init(x: length / 2, y: thickness / 2), .init(x: -length / 2, y: thickness / 2)]
            : [.init(x: -length / 2, y: height / 2), .init(x: length / 2, y: height / 2), .init(x: -length / 2, y: -height / 2)]
        return local.map { .init(x: x + $0.x * cos(angle) - $0.y * sin(angle), y: y + $0.x * sin(angle) + $0.y * cos(angle)) }
    }
    public func edge(nearest point: StrokeSample) -> Double {
        guard kind != .ruler else { return (point.x - x) * -sin(angle) + (point.y - y) * cos(angle) >= 0 ? 1 : -1 }
        let corners = vertices
        let index = corners.indices.min { a, b in
            ShapeGeometry.segmentDistance(point, corners[a], corners[(a + 1) % corners.count]) <
                ShapeGeometry.segmentDistance(point, corners[b], corners[(b + 1) % corners.count])
        } ?? 0
        return Double(index)
    }
    public func project(_ point: StrokeSample, edge: Double, width: Double, height: Double) -> StrokeSample? {
        guard [x, y, angle, thickness, length, point.x, point.y, edge, width, height].allSatisfy(\.isFinite), width > 0, height > 0, thickness > 0, length > 0 else { return nil }
        let ux: Double, uy: Double, ox: Double, oy: Double
        if kind == .ruler {
            ux = cos(angle); uy = sin(angle)
            let offset = min(1, max(-1, edge)) * thickness / 2
            ox = x - uy * offset; oy = y + ux * offset
        } else {
            let corners = vertices
            guard (0...2).contains(edge), edge.rounded() == edge else { return nil }
            let a = corners[Int(edge)], b = corners[(Int(edge) + 1) % corners.count]
            let span = hypot(b.x - a.x, b.y - a.y)
            guard span.isFinite, span > 0 else { return nil }
            ux = (b.x - a.x) / span; uy = (b.y - a.y) / span; ox = a.x; oy = a.y
        }
        var low = -Double.infinity, high = Double.infinity
        for (origin, direction, bound) in [(ox, ux, width), (oy, uy, height)] {
            if abs(direction) < 1e-9 { if origin < 0 || origin > bound { return nil } }
            else {
                let a = -origin / direction, b = (bound - origin) / direction
                low = max(low, min(a, b)); high = min(high, max(a, b))
            }
        }
        guard low <= high else { return nil }
        let t = min(high, max(low, (point.x - ox) * ux + (point.y - oy) * uy))
        return StrokeSample(x: ox + ux * t, y: oy + uy * t)
    }
    public mutating func snapAngle() {
        guard angle.isFinite else { angle = 0; return }
        angle = atan2(sin(angle), cos(angle))
        let target = (angle / (.pi / 4)).rounded() * (.pi / 4)
        if abs(angle - target) <= 6 * .pi / 180 { angle = target }
    }
}
