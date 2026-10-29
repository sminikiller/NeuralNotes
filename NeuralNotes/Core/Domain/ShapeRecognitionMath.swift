import Foundation

enum ShapeRecognitionMath {
    static func distance(_ a: StrokeSample, _ b: StrokeSample) -> Double { hypot(b.x - a.x, b.y - a.y) }
    static func length(_ points: [StrokeSample]) -> Double {
        guard points.count > 1 else { return 0 }
        var value = 0.0
        for index in 1..<points.count { value += distance(points[index - 1], points[index]) }
        return value
    }
    static func resample(_ points: [StrokeSample], count: Int = 64) -> [StrokeSample] {
        let total = length(points)
        guard points.count > 1, total > 0, total.isFinite else { return [] }
        let step = total / Double(count - 1)
        var result: [StrokeSample] = [points[0]], index = 1, walked = 0.0
        for sample in 1..<count {
            let target = min(total, Double(sample) * step)
            while index < points.count - 1 && walked + distance(points[index - 1], points[index]) < target {
                walked += distance(points[index - 1], points[index]); index += 1
            }
            let a = points[index - 1], b = points[index], segment = distance(a, b)
            let t = min(1, max(0, (target - walked) / max(0.000001, segment)))
            result.append(.init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }
    static func simplify(_ points: [StrokeSample], tolerance: Double) -> [StrokeSample] {
        guard points.count > 2 else { return points }
        let a = points[0], b = points[points.count - 1]
        var maximum = 0.0, selected = 0
        for index in 1..<(points.count - 1) {
            let error = ShapeGeometry.segmentDistance(points[index], a, b)
            if error > maximum { maximum = error; selected = index }
        }
        if maximum <= tolerance { return [a, b] }
        let left = simplify(Array(points[...selected]), tolerance: tolerance)
        let right = simplify(Array(points[selected...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }
    static func hasDistinctCorners(_ input: [StrokeSample]) -> Bool {
        let points = Array(input.dropLast()), count = points.count
        guard count >= 8 else { return false }
        var turns: [Double] = []
        for index in points.indices {
            // Average each tangent over two resampled intervals. Single-step
            // jitter on a smooth circle must not count as a polygon corner.
            let a = points[(index + count - 2) % count], b = points[index], c = points[(index + 2) % count]
            let ux = b.x - a.x, uy = b.y - a.y, vx = c.x - b.x, vy = c.y - b.y
            let product = max(0.001, hypot(ux, uy) * hypot(vx, vy))
            turns.append(acos(min(1, max(-1, (ux * vx + uy * vy) / product))))
        }
        let mean = turns.reduce(0, +) / Double(count)
        let peak = turns.max() ?? 0
        let flat = turns.filter { $0 < mean * 0.45 }.count
        return peak > 0.35 && peak > mean * 2.2 && Double(flat) / Double(count) > 0.12
    }
    static func corners(_ points: [StrokeSample], span: Double, tolerance: Double = 0.04) -> [StrokeSample] {
        guard let a = points.first,
              let farthest = points.indices.max(by: { distance(a, points[$0]) < distance(a, points[$1]) }), farthest > 0 else { return [] }
        let first = simplify(Array(points[...farthest]), tolerance: span * tolerance)
        let second = simplify(Array(points[farthest...]) + [a], tolerance: span * tolerance)
        var result = Array(first.dropLast()) + Array(second.dropLast())
        var changed = true
        while changed && result.count > 3 {
            changed = false
            for index in result.indices {
                let previous = result[(index + result.count - 1) % result.count], at = result[index], next = result[(index + 1) % result.count]
                if distance(previous, at) < span * 0.06 || ShapeGeometry.segmentDistance(at, previous, next) < span * 0.025 {
                    result.remove(at: index); changed = true; break
                }
            }
        }
        return result
    }
    static func variation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return .infinity }
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance) / mean
    }
    static func snappedAngle(_ degrees: Double) -> Double {
        let snapped = (degrees / 15).rounded() * 15
        return abs(snapped - degrees) <= 4 ? snapped : degrees
    }
    /// Kasa circle fit, translated to the centroid for numerical stability.
    static func circle(_ points: [StrokeSample]) -> (center: StrokeSample, radius: Double, error: Double)? {
        let n = Double(points.count)
        guard n >= 5 else { return nil }
        let cx = points.reduce(0.0) { $0 + $1.x } / n, cy = points.reduce(0.0) { $0 + $1.y } / n
        var xx = 0.0, yy = 0.0, xy = 0.0, xz = 0.0, yz = 0.0, z = 0.0
        for p in points {
            let x = p.x - cx, y = p.y - cy, r2 = x * x + y * y
            xx += x * x; yy += y * y; xy += x * y; xz += x * r2; yz += y * r2; z += r2
        }
        let determinant = xx * yy - xy * xy
        guard abs(determinant) > 0.0001 else { return nil }
        let a = (xz * yy - yz * xy) / (2 * determinant), b = (yz * xx - xz * xy) / (2 * determinant)
        let center = StrokeSample(x: cx + a, y: cy + b), radius = sqrt(z / n + a * a + b * b)
        guard radius.isFinite, radius > 0 else { return nil }
        let error = points.reduce(0.0) { $0 + abs(distance($1, center) - radius) } / (n * radius)
        return (center, radius, error)
    }
}
