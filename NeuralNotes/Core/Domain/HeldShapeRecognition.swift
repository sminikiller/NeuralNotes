import Foundation

/// Conservative recognition after an explicit hold. Numeric steps are kept
/// small and Double-typed so the iPad Playground compiler can check them quickly.
public enum HeldShapeRecognition {
    public static func recognize(_ input: [StrokeSample]) -> ShapeKind? {
        guard input.count >= 5 else { return nil }
        for point in input where !point.x.isFinite || !point.y.isFinite { return nil }
        guard !ScratchGesture.matches(input) else { return nil }
        let points = Array(input.suffix(2000))
        guard let first = points.first, let last = points.last else { return nil }
        var x0: Double = first.x, x1: Double = first.x
        var y0: Double = first.y, y1: Double = first.y
        var length: Double = 0
        var previous = first
        for point in points {
            x0 = min(x0, point.x); x1 = max(x1, point.x)
            y0 = min(y0, point.y); y1 = max(y1, point.y)
            length += distance(previous, point); previous = point
        }
        let width: Double = x1 - x0, height: Double = y1 - y0
        let span: Double = hypot(width, height)
        guard span >= 24, length.isFinite else { return nil }
        let chord: Double = distance(first, last)
        if chord >= 24 && length / chord < 1.18 {
            let dx: Double = last.x - first.x, dy: Double = last.y - first.y
            var maximumError: Double = 0
            for point in points {
                let offsetX: Double = point.x - first.x
                let offsetY: Double = point.y - first.y
                let cross: Double = dy * offsetX - dx * offsetY
                let error: Double = abs(cross) / chord
                maximumError = max(maximumError, error)
            }
            let tolerance: Double = max(3, chord * 0.045)
            if maximumError <= tolerance { return .line }
        }
        if arrowEndpoints(points) != nil { return .arrow }
        guard width >= 20, height >= 20, chord < span * 0.22,
              length > span * 1.5, length < span * 4.5 else { return nil }
        let sampled = resample(points, length: length)
        guard !sampled.isEmpty else { return nil }
        let tolerance: Double = max(3, min(width, height) * 0.09)
        var edgeCount = 0
        for point in sampled {
            let horizontal: Double = min(abs(point.x - x0), abs(point.x - x1))
            let vertical: Double = min(abs(point.y - y0), abs(point.y - y1))
            if min(horizontal, vertical) <= tolerance { edgeCount += 1 }
        }
        let edgeRatio: Double = Double(edgeCount) / Double(sampled.count)
        let corners = [StrokeSample(x: x0, y: y0), StrokeSample(x: x1, y: y0),
                       StrokeSample(x: x1, y: y1), StrokeSample(x: x0, y: y1)]
        var cornersFound = 0
        let cornerTolerance: Double = min(width, height) * 0.19
        for corner in corners {
            for point in sampled {
                if distance(point, corner) < cornerTolerance { cornersFound += 1; break }
            }
        }
        if edgeRatio > 0.88 && cornersFound == 4 { return .rectangle }
        if triangleVertices(sampled) != nil { return .triangle }
        let centerX: Double = (x0 + x1) / 2, centerY: Double = (y0 + y1) / 2
        let radiusX: Double = width / 2, radiusY: Double = height / 2
        var totalError: Double = 0, maximumError: Double = 0
        for point in sampled {
            let nx: Double = (point.x - centerX) / radiusX
            let ny: Double = (point.y - centerY) / radiusY
            let error: Double = abs(hypot(nx, ny) - 1)
            totalError += error; maximumError = max(maximumError, error)
        }
        let meanError: Double = totalError / Double(sampled.count)
        if meanError < 0.14 && maximumError < 0.4 { return .ellipse }
        return nil
    }
    public static func arrowEndpoints(_ points: [StrokeSample]) -> (StrokeSample, StrokeSample)? {
        guard points.count >= 5, let first = points.first,
              let tipIndex = points.indices.max(by: { distance(first, points[$0]) < distance(first, points[$1]) }),
              tipIndex > 0, tipIndex < points.count - 2 else { return nil }
        let tip = points[tipIndex], shaft = distance(first, tip)
        guard shaft >= 40 else { return nil }
        let dx = (tip.x - first.x) / shaft, dy = (tip.y - first.y) / shaft
        for p in points[...tipIndex] {
            let deviation = abs((p.x - first.x) * dy - (p.y - first.y) * dx)
            if deviation > max(3, shaft * 0.035) { return nil }
        }
        var left = false, right = false
        for p in points[tipIndex...] {
            let along = (p.x - first.x) * dx + (p.y - first.y) * dy
            let cross = (p.x - first.x) * dy - (p.y - first.y) * dx
            guard along >= shaft * 0.62, along <= shaft * 1.03, abs(cross) <= shaft * 0.35 else { return nil }
            if cross > shaft * 0.04 { left = true }
            if cross < -shaft * 0.04 { right = true }
        }
        return left && right ? (first, tip) : nil
    }
    /// Convex hull reduction followed by edge-distance validation retains a
    /// rotated triangle, while rejecting ellipses, rectangles and open outlines.
    public static func triangleVertices(_ input: [StrokeSample]) -> [StrokeSample]? {
        guard input.count >= 5, input.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let first = input.first, let last = input.last else { return nil }
        let sorted = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard let low = sorted.first, let high = sorted.last else { return nil }
        let span = hypot(high.x - low.x, (input.map(\.y).max() ?? 0) - (input.map(\.y).min() ?? 0))
        guard span >= 28, distance(first, last) < span * 0.22 else { return nil }
        func cross(_ a: StrokeSample, _ b: StrokeSample, _ c: StrokeSample) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        func half(_ values: [StrokeSample]) -> [StrokeSample] {
            var result: [StrokeSample] = []
            for p in values {
                while result.count >= 2 && cross(result[result.count - 2], result[result.count - 1], p) <= 0 { result.removeLast() }
                result.append(p)
            }; return result
        }
        var hull = Array(half(sorted).dropLast()) + Array(half(Array(sorted.reversed())).dropLast())
        guard hull.count >= 3 else { return nil }
        while hull.count > 3 {
            var best = 0, minimum = Double.infinity
            for i in hull.indices {
                let a = hull[(i + hull.count - 1) % hull.count], b = hull[i], c = hull[(i + 1) % hull.count]
                let height = abs(cross(a, c, b)) / max(1, distance(a, c))
                if height < minimum { minimum = height; best = i }
            }; hull.remove(at: best)
        }
        guard abs(cross(hull[0], hull[1], hull[2])) > span * span * 0.15 else { return nil }
        for p in input {
            var error = Double.infinity
            for i in 0..<3 {
                let a = hull[i], b = hull[(i + 1) % 3]
                let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
                let projection = denominator > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator : 0
                let t = min(1, max(0, projection))
                error = min(error, distance(p, StrokeSample(x: a.x + dx * t, y: a.y + dy * t)))
            }
            if error > max(3, span * 0.035) { return nil }
        }
        return hull
    }
    private static func distance(_ a: StrokeSample, _ b: StrokeSample) -> Double {
        let dx: Double = b.x - a.x, dy: Double = b.y - a.y
        return hypot(dx, dy)
    }
    private static func resample(_ points: [StrokeSample], length: Double) -> [StrokeSample] {
        var sampled: [StrokeSample] = []
        let step: Double = max(1, length / 160)
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let segmentLength: Double = distance(a, b)
            let estimate: Double = min(300, max(1, ceil(segmentLength / step)))
            let count = Int(estimate)
            for i in 0..<count {
                let t: Double = Double(i) / Double(count)
                let x: Double = a.x + (b.x - a.x) * t
                let y: Double = a.y + (b.y - a.y) * t
                sampled.append(StrokeSample(x: x, y: y))
            }
        }
        return sampled
    }
}
