import Foundation

public struct RulerGuide: Equatable, Sendable {
    public var x: Double, y: Double, angle: Double
    public static let halfWidth = 22.0
    public init(x: Double = 384, y: Double = 512, angle: Double = 0) { self.x = x; self.y = y; self.angle = angle }
    public func edge(nearest point: StrokeSample) -> Double {
        (point.x - x) * -sin(angle) + (point.y - y) * cos(angle) >= 0 ? 1 : -1
    }
    public func project(_ point: StrokeSample, edge: Double, width: Double, height: Double) -> StrokeSample? {
        guard [x, y, angle, point.x, point.y, edge, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        let ux = cos(angle), uy = sin(angle), offset = min(1, max(-1, edge)) * Self.halfWidth
        let ox = x - uy * offset, oy = y + ux * offset
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
