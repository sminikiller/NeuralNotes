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
