import Foundation

/// Page units, with zero at the right edge and positive angles toward the top.
/// The guide rotation follows the page's clockwise, downward-y coordinates.
public struct ProtractorGuide: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case semicircle, circle
        public init(from decoder: Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .semicircle
        }
    }
    public enum Mode: Equatable, Sendable { case arc, ray }
    public var x: Double, y: Double, radius: Double, rotation: Double
    public var kind: Kind
    public init(x: Double = 384, y: Double = 512, radius: Double = 180, rotation: Double = 0, kind: Kind = .semicircle) {
        self.x = x; self.y = y; self.radius = radius; self.rotation = rotation; self.kind = kind
    }
    public var isValid: Bool {
        [x, y, radius, rotation].allSatisfy(\.isFinite) && abs(x) <= 1_000_000 && abs(y) <= 1_000_000 && (24...10000).contains(radius)
    }
    public var maximumAngle: Double { kind == .circle ? 2 * .pi : .pi }
    public func point(at angle: Double, distance: Double? = nil) -> StrokeSample? {
        guard isValid, angle.isFinite, distance?.isFinite != false else { return nil }
        let a = rotation.truncatingRemainder(dividingBy: 2 * .pi) - angle
        // A valid 20000 x 20000 page has diagonals longer than 20000 pt.
        let r = max(0, min(30000, distance ?? radius))
        return StrokeSample(x: x + cos(a) * r, y: y + sin(a) * r)
    }
    public func angle(at point: StrokeSample) -> Double? {
        guard isValid, point.x.isFinite, point.y.isFinite else { return nil }
        let angle = rotation.truncatingRemainder(dividingBy: 2 * .pi) - atan2(point.y - y, point.x - x)
        let normalized = Self.normalized(angle)
        if kind == .circle || normalized <= .pi { return normalized }
        return normalized - .pi < 2 * .pi - normalized ? .pi : 0
    }
    /// A gesture latches its mode at touch-down; moving away cannot release it.
    public func mode(at point: StrokeSample, zoom: Double) -> Mode? {
        guard isValid, zoom.isFinite, zoom > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let tolerance = 12 / max(0.01, zoom), distance = hypot(point.x - x, point.y - y)
        if distance <= tolerance { return .ray }
        guard let a = angle(at: point), let nearest = self.point(at: a), hypot(point.x - nearest.x, point.y - nearest.y) <= tolerance else { return nil }
        return .arc
    }
    public func project(_ point: StrokeSample, mode: Mode) -> StrokeSample? {
        guard let angle = angle(at: point) else { return nil }
        switch mode {
        case .arc: return self.point(at: angle)
        case .ray: return self.point(at: Self.snapped(angle), distance: hypot(point.x - x, point.y - y))
        }
    }
    public static func snapped(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let value = normalized(angle), degrees = value * 180 / .pi
        for step in [90.0, 45, 30, 15, 5] {
            let target = (degrees / step).rounded() * step
            if abs(target - degrees) <= 2 { return normalized(target * .pi / 180) }
        }
        return degrees.rounded() * .pi / 180
    }
    public static func difference(_ first: Double, _ second: Double) -> Double? {
        guard first.isFinite, second.isFinite else { return nil }
        let delta = abs(normalized(first) - normalized(second))
        return min(delta, 2 * .pi - delta)
    }
    public static func centimeters(points: Double) -> Double? {
        guard points.isFinite, points >= 0 else { return nil }
        return points / 72 * 2.54
    }
    private static func normalized(_ angle: Double) -> Double {
        let result = angle.truncatingRemainder(dividingBy: 2 * .pi)
        return result < 0 ? result + 2 * .pi : result
    }
}
