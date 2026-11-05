import Foundation

public enum HandwritingCleanup {
    public enum Strength: String, CaseIterable, Equatable, Sendable { case light, medium, strong }
    private struct Knot { let point: StrokeSample; let position: Double }
    /// Returns the same number of coordinate samples. Pressure/width/opacity
    /// are deliberately not resampled here: the native adapter preserves the
    /// original fields at every control-point index, even on straight segments.
    public static func points(_ points: [StrokeSample], strength: Strength) -> [StrokeSample] {
        guard points.count >= 3, points.count <= 200_000, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return points }
        let tolerance: Double = strength == .light ? 0.35 : strength == .medium ? 0.7 : 1.2
        let retained = simplify(points, tolerance: tolerance)
        var guide = retained.map { Knot(point: points[$0], position: Double($0)) }
        for _ in 0..<(strength == .strong ? 2 : 1) {
            var next = [guide[0]]
            let amount = strength == .light ? 0.12 : 0.25
            for (a, b) in zip(guide, guide.dropFirst()) {
                next.append(interpolate(a, b, amount)); next.append(interpolate(a, b, 1 - amount))
            }
            next.append(guide[guide.count - 1]); guide = next
        }
        var index = 0
        return points.indices.map { original in
            if original == 0 || original == points.count - 1 { return points[original] }
            let position = Double(original)
            while index + 1 < guide.count - 1 && guide[index + 1].position < position { index += 1 }
            let a = guide[index], b = guide[min(guide.count - 1, index + 1)]
            let fraction = max(0, min(1, (position - a.position) / max(0.000001, b.position - a.position)))
            return interpolate(a, b, fraction).point
        }
    }
    private static func interpolate(_ a: Knot, _ b: Knot, _ t: Double) -> Knot {
        Knot(point: .init(x: a.point.x + (b.point.x - a.point.x) * t, y: a.point.y + (b.point.y - a.point.y) * t),
            position: a.position + (b.position - a.position) * t)
    }
    private static func simplify(_ points: [StrokeSample], tolerance: Double) -> [Int] {
        var kept: Set<Int> = [0, points.count - 1], pending = [(0, points.count - 1)]
        var evaluations = 0
        let budget = max(4096, min(1_000_000, points.count * 64))
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }
            let a = points[first], b = points[last], dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            var peak = tolerance, chosen: Int?
            for i in (first + 1)..<last {
                evaluations += 1
                // An adversarial zigzag must not turn RDP into a quadratic UI
                // stall. Chaikin can safely smooth the original guide instead.
                if evaluations > budget { return Array(points.indices) }
                let p = points[i], t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
                let distance = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if distance > peak { peak = distance; chosen = i }
            }
            if let chosen { kept.insert(chosen); pending.append((first, chosen)); pending.append((chosen, last)) }
        }
        return kept.sorted()
    }
}
