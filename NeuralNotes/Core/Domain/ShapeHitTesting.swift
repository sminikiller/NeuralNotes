import Foundation

public extension ShapeGeometry {
    static func connectionPoints(_ shape: ShapeElement) -> [StrokeSample] {
        var local = shape; local.rotation = nil
        guard let outline = polylines(path(for: local)).first, outline.count >= 2 else { return [] }
        if shape.kind.isOpen {
            return ShapeRecognitionMath.resample(outline, count: 3).map { rotate($0, shape: shape) }
        }
        let center = StrokeSample(x: shape.x + shape.width / 2, y: shape.y + shape.height / 2)
        let directions = [sample(0, -1), sample(1, 0), sample(0, 1), sample(-1, 0)]
        var result: [StrokeSample] = []
        for direction in directions {
            var farthest: Double?
            for index in 1..<outline.count {
                let a = outline[index - 1], b = outline[index]
                let sx = b.x - a.x, sy = b.y - a.y
                let denominator = direction.x * sy - direction.y * sx
                guard abs(denominator) > 0.000001 else { continue }
                let px = a.x - center.x, py = a.y - center.y
                let distance = (px * sy - py * sx) / denominator
                let along = (px * direction.y - py * direction.x) / denominator
                if distance >= 0, (-0.000001...1.000001).contains(along), distance > (farthest ?? -1) { farthest = distance }
            }
            if let distance = farthest {
                let point = sample(center.x + direction.x * distance, center.y + direction.y * distance)
                result.append(rotate(point, shape: shape))
            }
        }
        return result
    }
    static func polylines(_ path: ShapePath, steps: Int = 32) -> [[StrokeSample]] {
        let count = min(128, max(4, steps))
        var lines: [[StrokeSample]] = [], line: [StrokeSample] = [], current = sample(0, 0)
        func curve(_ controls: [StrokeSample], end: StrokeSample) -> [StrokeSample] {
            let start = current
            return (1...count).map { index in
                let t = Double(index) / Double(count), u = 1 - t
                if controls.count == 1 {
                    let c = controls[0]
                    return sample(u * u * start.x + 2 * u * t * c.x + t * t * end.x,
                                  u * u * start.y + 2 * u * t * c.y + t * t * end.y)
                }
                let a = controls[0], b = controls[1], u2 = u * u, t2 = t * t
                let x = u2 * u * start.x + 3 * u2 * t * a.x + 3 * u * t2 * b.x + t2 * t * end.x
                let y = u2 * u * start.y + 3 * u2 * t * a.y + 3 * u * t2 * b.y + t2 * t * end.y
                return sample(x, y)
            }
        }
        for command in path.commands {
            switch command {
            case .move(let p): if !line.isEmpty { lines.append(line) }; line = [p]; current = p
            case .line(let p): line.append(p); current = p
            case .quad(let c, let p): line += curve([c], end: p); current = p
            case .cubic(let a, let b, let p): line += curve([a, b], end: p); current = p
            case .close: if let first = line.first { line.append(first); current = first }
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
    static func hit(_ point: StrokeSample, shape: ShapeElement, zoom: Double, tolerance: Double = 8) -> Bool {
        let threshold = tolerance / max(0.05, zoom) + shape.lineWidth / 2
        let paths = [path(for: shape)] + arrowPaths(for: shape)
        for (index, path) in paths.enumerated() {
            for line in polylines(path) {
                if index == 0 && !shape.kind.isOpen && shape.fill != nil && (shape.fillOpacity ?? 0.25) > 0 && contains(point, polygon: line) { return true }
                if index > 0 && shape.arrowStyle == .filled && contains(point, polygon: line) { return true }
                for offset in 1..<line.count where segmentDistance(point, line[offset - 1], line[offset]) <= threshold { return true }
            }
        }
        return false
    }
    static func bounds(_ shape: ShapeElement) -> (x: Double, y: Double, width: Double, height: Double) {
        let points = ([path(for: shape)] + arrowPaths(for: shape)).flatMap { polylines($0).flatMap { $0 } }
        guard let first = points.first else { return (shape.x, shape.y, shape.width, shape.height) }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for p in points { x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y) }
        return (x0, y0, max(1, x1 - x0), max(1, y1 - y0))
    }
    static func contains(_ p: StrokeSample, polygon: [StrokeSample]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false, j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let crossX = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < crossX { inside.toggle() }
            }; j = i
        }
        return inside
    }
    static func segmentDistance(_ p: StrokeSample, _ a: StrokeSample, _ b: StrokeSample) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
        let projection = denominator > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator : 0
        let t = min(1, max(0, projection))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
