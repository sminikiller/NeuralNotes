import Foundation

public struct ShapeRecognitionContext: Sendable {
    public var duration: Double, nearWriting: Bool
    public init(duration: Double = 1, nearWriting: Bool = false) { self.duration = duration; self.nearWriting = nearWriting }
}
public struct ShapeRecognitionResult: Sendable {
    public var shape: ShapeElement
    public var confidence: Double
    public init(shape: ShapeElement, confidence: Double) { self.shape = shape; self.confidence = confidence }
}

public enum ShapeRecognizer {
    public static func recognize(_ input: [StrokeSample], mode: ShapeRecognitionMode = .hold,
                                 enabled: [ShapeKind] = ShapeKind.allCases,
                                 context: ShapeRecognitionContext = .init()) -> ShapeRecognitionResult? {
        guard mode != .off, (5...10_000).contains(input.count),
              input.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1_000_000 && abs($0.y) < 1_000_000 }),
              !ScratchGesture.matches(input) else { return nil }
        let sampled = ShapeRecognitionMath.resample(input)
        guard sampled.count == 64, let first = sampled.first, let last = sampled.last else { return nil }
        let x0 = sampled.map(\.x).min()!, x1 = sampled.map(\.x).max()!
        let y0 = sampled.map(\.y).min()!, y1 = sampled.map(\.y).max()!
        let span = hypot(x1 - x0, y1 - y0), length = ShapeRecognitionMath.length(sampled)
        guard span >= 24, length > 0 else { return nil }
        if mode == .automatic && (context.nearWriting || context.duration < 0.18 || span < 40) { return nil }
        func accepted(_ shape: ShapeElement, _ confidence: Double) -> ShapeRecognitionResult? {
            guard enabled.contains(shape.kind), confidence >= (mode == .automatic ? 0.85 : 0.6) else { return nil }
            return ShapeRecognitionResult(shape: shape, confidence: confidence)
        }
        if let ends = HeldShapeRecognition.arrowEndpoints(input),
           let shape = ShapeElement.dragged(kind: .arrow, from: ends.0, to: ends.1, color: .black, lineWidth: 3),
           let value = accepted(shape, 0.96) { return value }
        if let ends = HeldShapeRecognition.lineEndpoints(input),
           let shape = ShapeElement.dragged(kind: .line, from: ends.0, to: snappedEnd(ends.0, ends.1), color: .black, lineWidth: 3) {
            let error = sampled.map { ShapeGeometry.segmentDistance($0, ends.0, ends.1) }.max() ?? span
            if let value = accepted(shape, max(0.6, 0.99 - error / span * 2)) { return value }
        }
        let gap = ShapeRecognitionMath.distance(first, last)
        let closed = gap / length < 0.12 && gap < span * 0.14
        if mode == .automatic && closed && min(x1 - x0, y1 - y0) < 48 { return nil }
        if !closed {
            if let arc = arc(sampled), let value = accepted(arc.shape, arc.confidence) { return value }
            return nil
        }
        let sharp = ShapeRecognitionMath.hasDistinctCorners(sampled)
        // A high-sided regular polygon also fits an ellipse. Distinct corners
        // separated by straight edges take precedence; smooth circles do not.
        // Use finer RDP only with this evidence, retaining all 12 polygon sides.
        let vertices = ShapeRecognitionMath.corners(sampled, span: span, tolerance: sharp ? 0.018 : 0.04)
        let fitted = (3...24).contains(vertices.count) ? ShapePolygonRecognition.recognize(vertices, samples: sampled, span: span) : nil
        if sharp, let fitted { return accepted(fitted.shape, fitted.confidence) }
        if let ellipse = ellipse(sampled) { return accepted(ellipse.shape, ellipse.confidence) }
        if let fitted { return accepted(fitted.shape, fitted.confidence) }
        return nil
    }
    public static func snappedEnd(_ a: StrokeSample, _ b: StrokeSample) -> StrokeSample {
        let distance = hypot(b.x - a.x, b.y - a.y)
        let angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        let snapped = ShapeRecognitionMath.snappedAngle(angle) * .pi / 180
        return StrokeSample(x: a.x + distance * cos(snapped), y: a.y + distance * sin(snapped))
    }
    private static func arc(_ points: [StrokeSample]) -> ShapeRecognitionResult? {
        guard let fit = ShapeRecognitionMath.circle(points), fit.error < 0.06, fit.radius < 20_000 else { return nil }
        var sweep = 0.0, previous = atan2(points[0].y - fit.center.y, points[0].x - fit.center.x), reversals = 0
        var direction = 0.0
        for p in points.dropFirst() {
            let angle = atan2(p.y - fit.center.y, p.x - fit.center.x)
            var delta = angle - previous
            while delta > .pi { delta -= 2 * .pi }; while delta < -.pi { delta += 2 * .pi }
            if abs(delta) > 0.015 {
                if direction != 0 && delta * direction < 0 { reversals += 1 }
                direction = delta
            }
            sweep += delta; previous = angle
        }
        guard (Double.pi / 6...11 * Double.pi / 6).contains(abs(sweep)), reversals <= 2 else { return nil }
        var shape = ShapeElement(kind: .arc, x: fit.center.x - fit.radius, y: fit.center.y - fit.radius,
                                 width: fit.radius * 2, height: fit.radius * 2)
        shape.arcStart = atan2(points[0].y - fit.center.y, points[0].x - fit.center.x); shape.arcSweep = sweep
        return .init(shape: shape, confidence: min(0.99, 0.99 - fit.error * 2))
    }
    private static func ellipse(_ points: [StrokeSample]) -> ShapeRecognitionResult? {
        let values = Array(points.dropLast()), n = Double(values.count)
        let cx = values.reduce(0.0) { $0 + $1.x } / n, cy = values.reduce(0.0) { $0 + $1.y } / n
        var xx = 0.0, yy = 0.0, xy = 0.0
        for p in values { xx += pow(p.x - cx, 2); yy += pow(p.y - cy, 2); xy += (p.x - cx) * (p.y - cy) }
        let angle = atan2(2 * xy, xx - yy) / 2, c = cos(angle), s = sin(angle)
        let local = values.map { StrokeSample(x: ($0.x - cx) * c + ($0.y - cy) * s, y: -($0.x - cx) * s + ($0.y - cy) * c) }
        let x0 = local.map(\.x).min()!, x1 = local.map(\.x).max()!, y0 = local.map(\.y).min()!, y1 = local.map(\.y).max()!
        var rx = (x1 - x0) / 2, ry = (y1 - y0) / 2
        guard min(rx, ry) >= 12 else { return nil }
        let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
        let errors = local.map { abs(hypot(($0.x - mx) / rx, ($0.y - my) / ry) - 1) }
        let mean = errors.reduce(0, +) / n
        guard mean < 0.04, (errors.max() ?? 1) < 0.12 else { return nil }
        if max(rx, ry) / min(rx, ry) <= 1.1 { let radius = (rx + ry) / 2; rx = radius; ry = radius }
        let centerX = cx + mx * c - my * s, centerY = cy + mx * s + my * c
        var shape = ShapeElement(kind: .ellipse, x: centerX - rx, y: centerY - ry, width: 2 * rx, height: 2 * ry)
        shape.rotation = rx == ry ? nil : ShapeRecognitionMath.snappedAngle(angle * 180 / .pi)
        return .init(shape: shape, confidence: 0.99 - mean * 2)
    }
}
