import Foundation

enum ShapePolygonRecognition {
    static func recognize(_ vertices: [StrokeSample], samples: [StrokeSample], span: Double) -> ShapeRecognitionResult? {
        let count = vertices.count
        guard count >= 3 else { return nil }
        var maximumError = 0.0
        for p in samples {
            var error = Double.infinity
            for i in vertices.indices { error = min(error, ShapeGeometry.segmentDistance(p, vertices[i], vertices[(i + 1) % count])) }
            maximumError = max(maximumError, error)
        }
        guard maximumError <= span * 0.06 else { return nil }
        let confidence = min(0.99, 0.99 - maximumError / span * 2)
        if count == 3 {
            return .init(shape: normalized(ShapeTriangleFit.corrected(vertices), kind: .triangle), confidence: confidence)
        }
        if count == 4, let shape = quadrilateral(vertices) { return .init(shape: shape, confidence: confidence) }
        let cx = vertices.reduce(0.0) { $0 + $1.x } / Double(count)
        let cy = vertices.reduce(0.0) { $0 + $1.y } / Double(count)
        let radii = vertices.map { hypot($0.x - cx, $0.y - cy) }
        if count >= 8, count <= 24, count % 2 == 0 {
            let even = radii.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let odd = radii.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            let a = even.reduce(0, +) / Double(even.count), b = odd.reduce(0, +) / Double(odd.count)
            let ratio = min(a, b) / max(a, b)
            if (0.3...0.7).contains(ratio), ShapeRecognitionMath.variation(even) < 0.12, ShapeRecognitionMath.variation(odd) < 0.12 {
                let outer = vertices[a > b ? 0 : 1], radius = max(a, b)
                var shape = ShapeElement(kind: .star, x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                shape.sides = count / 2; shape.innerRatio = ratio
                shape.rotation = ShapeRecognitionMath.snappedAngle((atan2(outer.y - cy, outer.x - cx) + .pi / 2) * 180 / .pi)
                return .init(shape: shape, confidence: confidence)
            }
        }
        let lengths = vertices.indices.map { ShapeRecognitionMath.distance(vertices[$0], vertices[($0 + 1) % count]) }
        var turns: [Double] = []
        for i in vertices.indices {
            let a = vertices[(i + count - 1) % count], b = vertices[i], c = vertices[(i + 1) % count]
            let product = max(0.001, ShapeRecognitionMath.distance(a, b) * ShapeRecognitionMath.distance(b, c))
            let cosine = min(1, max(-1, ((b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)) / product))
            turns.append(acos(cosine))
        }
        if (5...12).contains(count), ShapeRecognitionMath.variation(lengths) < 0.18,
           ShapeRecognitionMath.variation(turns) < 0.18, ShapeRecognitionMath.variation(radii) < 0.12 {
            let radius = radii.reduce(0, +) / Double(count)
            var shape = ShapeElement(kind: .polygon, x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            shape.sides = count
            shape.rotation = ShapeRecognitionMath.snappedAngle((atan2(vertices[0].y - cy, vertices[0].x - cx) + .pi / 2 + .pi / Double(count)) * 180 / .pi)
            return .init(shape: shape, confidence: confidence)
        }
        guard count <= 12 else { return nil }
        return .init(shape: normalized(vertices, kind: .freePolygon), confidence: confidence * 0.9)
    }
    private static func normalized(_ vertices: [StrokeSample], kind: ShapeKind) -> ShapeElement {
        let x = vertices.map(\.x).min()!, y = vertices.map(\.y).min()!
        let width = max(1, vertices.map(\.x).max()! - x), height = max(1, vertices.map(\.y).max()! - y)
        var shape = ShapeElement(kind: kind, x: x, y: y, width: width, height: height)
        shape.vertices = vertices.map { ShapeEndpoint(x: min(1, max(0, ($0.x - x) / width)), y: min(1, max(0, ($0.y - y) / height))) }
        return shape
    }
    private static func quadrilateral(_ points: [StrokeSample]) -> ShapeElement? {
        let a = points[0], b = points[1], c = points[2], d = points[3]
        let ab = ShapeRecognitionMath.distance(a, b), bc = ShapeRecognitionMath.distance(b, c)
        guard min(ab, bc) >= 12 else { return nil }
        let lengths = [ab, bc, ShapeRecognitionMath.distance(c, d), ShapeRecognitionMath.distance(d, a)]
        let diagonal1 = ShapeRecognitionMath.distance(a, c), diagonal2 = ShapeRecognitionMath.distance(b, d)
        let diagonalDot = abs((c.x - a.x) * (d.x - b.x) + (c.y - a.y) * (d.y - b.y)) / max(1, diagonal1 * diagonal2)
        let edgeAngle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        let edgeAxis = abs(edgeAngle - (edgeAngle / 90).rounded() * 90)
        let diagonalAngle = atan2(c.y - a.y, c.x - a.x) * 180 / .pi
        let diagonalAxis = abs(diagonalAngle - (diagonalAngle / 90).rounded() * 90)
        let rhombus = diagonalDot < sin(8 * .pi / 180) && ShapeRecognitionMath.variation(lengths) < 0.12
        if rhombus && diagonalAxis <= 8 && edgeAxis > 8 { return normalizedDiamond(points) }
        var rectangular = true
        for i in 0..<4 {
            let p = points[i], q = points[(i + 1) % 4], r = points[(i + 2) % 4]
            let cosine = abs((q.x - p.x) * (r.x - q.x) + (q.y - p.y) * (r.y - q.y))
            let product = max(1, ShapeRecognitionMath.distance(p, q) * ShapeRecognitionMath.distance(q, r))
            if cosine / product > sin(8 * .pi / 180) { rectangular = false }
        }
        let cx = points.reduce(0.0) { $0 + $1.x } / 4, cy = points.reduce(0.0) { $0 + $1.y } / 4
        if rectangular {
            var width = (ab + lengths[2]) / 2, height = (bc + lengths[3]) / 2
            if max(width, height) / min(width, height) <= 1.1 { let side = (width + height) / 2; width = side; height = side }
            var shape = ShapeElement(kind: .rectangle, x: cx - width / 2, y: cy - height / 2, width: width, height: height)
            shape.rotation = ShapeRecognitionMath.snappedAngle(edgeAngle)
            return shape
        }
        if rhombus {
            var shape = ShapeElement(kind: .diamond, x: cx - diagonal1 / 2, y: cy - diagonal2 / 2, width: diagonal1, height: diagonal2)
            shape.rotation = ShapeRecognitionMath.snappedAngle(diagonalAngle)
            return shape
        }
        return nil
    }
    private static func normalizedDiamond(_ vertices: [StrokeSample]) -> ShapeElement {
        let bounds = normalized(vertices, kind: .diamond)
        return ShapeElement(kind: .diamond, x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
    }
}
