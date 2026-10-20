import Foundation

/// Conservative geometry recognition. Called only after the endpoint has stayed
/// still for the hold interval, never on an ordinary lifted handwriting stroke.
public enum HeldShapeRecognition {
    public static func recognize(_ input: [StrokeSample]) -> ShapeKind? {
        guard input.count >= 5, input.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), !ScratchGesture.matches(input) else { return nil }
        let points = Array(input.suffix(2000))
        guard let first = points.first, let last = points.last else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let w = x1 - x0, h = y1 - y0, span = hypot(w, h)
        guard span >= 24 else { return nil }
        let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let chord = hypot(last.x - first.x, last.y - first.y)
        if chord >= 24, length / chord < 1.18 {
            let error = points.map { abs((last.y - first.y) * ($0.x - first.x) - (last.x - first.x) * ($0.y - first.y)) / chord }.max() ?? .infinity
            if error <= max(3, chord * 0.045) { return .line }
        }
        guard w >= 20, h >= 20, chord < span * 0.22, length > span * 1.5, length < span * 4.5 else { return nil }
        // Arc-length weighted samples avoid mistaking a circle with a few
        // heavily sampled corners for a rectangle (or a fast polygon for ink).
        var sampled: [StrokeSample] = []
        let step = max(1, length / 160)
        for (a, b) in zip(points, points.dropFirst()) {
            let distance = hypot(b.x - a.x, b.y - a.y)
            let count = min(300, max(1, Int(ceil(distance / step))))
            for i in 0..<count {
                let t = Double(i) / Double(count)
                sampled.append(StrokeSample(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        let tolerance = max(3, min(w, h) * 0.09)
        let edgeRatio = Double(sampled.filter { min(min(abs($0.x - x0), abs($0.x - x1)), min(abs($0.y - y0), abs($0.y - y1))) <= tolerance }.count) / Double(max(1, sampled.count))
        let corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        if edgeRatio > 0.88, corners.allSatisfy({ c in sampled.contains { hypot($0.x - c.0, $0.y - c.1) < min(w, h) * 0.19 } }) { return .rectangle }
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        let errors = sampled.map { abs(hypot(($0.x - cx) / (w / 2), ($0.y - cy) / (h / 2)) - 1) }
        let mean = errors.reduce(0, +) / Double(max(1, errors.count))
        if mean < 0.14, (errors.max() ?? 1) < 0.4 { return .ellipse }
        return nil
    }
}
