import Foundation

enum ShapeTriangleFit {
    static func corrected(_ input: [StrokeSample]) -> [StrokeSample] {
        guard input.count == 3 else { return input }
        var points = input, angles: [Double] = []
        for i in 0..<3 {
            let p = input[i], a = input[(i + 1) % 3], b = input[(i + 2) % 3]
            let denominator = max(0.001, hypot(a.x - p.x, a.y - p.y) * hypot(b.x - p.x, b.y - p.y))
            let cosine = min(1, max(-1, ((a.x - p.x) * (b.x - p.x) + (a.y - p.y) * (b.y - p.y)) / denominator))
            angles.append(acos(cosine) * 180 / .pi)
        }
        if angles.allSatisfy({ abs($0 - 60) <= 8 }) {
            let cx = input.reduce(0.0) { $0 + $1.x } / 3, cy = input.reduce(0.0) { $0 + $1.y } / 3
            let radius = input.reduce(0.0) { $0 + hypot($1.x - cx, $1.y - cy) } / 3
            let orientation = atan2(input[0].y - cy, input[0].x - cx)
            let cross = (input[1].x - input[0].x) * (input[2].y - input[0].y) - (input[1].y - input[0].y) * (input[2].x - input[0].x)
            let sign = cross >= 0 ? 1.0 : -1.0
            points = (0..<3).map { index in
                let angle = orientation + sign * Double(index) * 2 * .pi / 3
                return .init(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            }
        } else if let index = angles.indices.first(where: { abs(angles[$0] - 90) <= 8 }) {
            let at = input[index], a = input[(index + 1) % 3], b = input[(index + 2) % 3]
            let ax = a.x - at.x, ay = a.y - at.y, length = max(1, hypot(ax, ay)), radius = hypot(b.x - at.x, b.y - at.y)
            let sign = ax * (b.y - at.y) - ay * (b.x - at.x) >= 0 ? 1.0 : -1.0
            points[(index + 2) % 3] = .init(x: at.x - ay / length * radius * sign, y: at.y + ax / length * radius * sign)
        }
        let angle = atan2(points[1].y - points[0].y, points[1].x - points[0].x) * 180 / .pi
        let delta = (ShapeRecognitionMath.snappedAngle(angle) - angle) * .pi / 180
        let cx = points.reduce(0.0) { $0 + $1.x } / 3, cy = points.reduce(0.0) { $0 + $1.y } / 3
        return points.map { p in
            let dx = p.x - cx, dy = p.y - cy
            return .init(x: cx + dx * cos(delta) - dy * sin(delta), y: cy + dx * sin(delta) + dy * cos(delta))
        }
    }
}
