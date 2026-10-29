import Foundation

/// A tiny visibility grid around the two attached objects. Normal exit stubs
/// protect rotated contours; the middle route is orthogonal and avoids boxes.
enum ConnectorOrthogonal {
    static func path(_ c: ConnectorElement, objects: [UUID: ConnectorObject]) -> ShapePath {
        let a = ConnectorGeometry.resolve(c.from, objects: objects), b = ConnectorGeometry.resolve(c.to, objects: objects)
        let horizontal = abs(b.x - a.x) >= abs(b.y - a.y)
        let direction = StrokeSample(x: horizontal ? (b.x >= a.x ? 1 : -1) : 0, y: horizontal ? 0 : (b.y >= a.y ? 1 : -1))
        let n1 = ConnectorGeometry.normal(c.from, at: a, objects: objects, fallback: direction)
        let n2 = ConnectorGeometry.normal(c.to, at: b, objects: objects, fallback: .init(x: -direction.x, y: -direction.y))
        let first = c.from.objectID.flatMap { objects[$0] }, last = c.to.objectID.flatMap { objects[$0] }
        let s = stub(a, normal: n1, object: first), t = stub(b, normal: n2, object: last)
        var obstacles = [SnapRect](), seen = Set<UUID>()
        for object in [first, last].compactMap({ $0 }) where seen.insert(object.id).inserted { obstacles.append(object.bounds) }
        var middle: [StrokeSample]
        if let waypoint = c.controlPoints?.first, !obstacles.contains(where: { inside(waypoint, $0) }) {
            middle = route(s, waypoint, obstacles: obstacles) + route(waypoint, t, obstacles: obstacles).dropFirst()
        } else { middle = route(s, t, obstacles: obstacles) }
        var points = [a] + middle + [b]
        points = points.enumerated().filter { i, p in i == 0 || hypot(p.x - points[i - 1].x, p.y - points[i - 1].y) > 0.0001 }.map(\.element)
        guard let start = points.first else { return ShapePath() }
        return ShapePath([.move(start)] + points.dropFirst().map { .line($0) })
    }
    private static func stub(_ point: StrokeSample, normal: StrokeSample, object: ConnectorObject?) -> StrokeSample {
        guard let object else { return point }
        let box = object.bounds
        var exits: [Double] = []
        if normal.x > 0.00001 { exits.append((box.maxX + 12 - point.x) / normal.x) }
        if normal.x < -0.00001 { exits.append((box.x - 12 - point.x) / normal.x) }
        if normal.y > 0.00001 { exits.append((box.maxY + 12 - point.y) / normal.y) }
        if normal.y < -0.00001 { exits.append((box.y - 12 - point.y) / normal.y) }
        return ConnectorGeometry.offset(point, normal, max(20, exits.filter { $0 > 0 }.min() ?? 20))
    }
    private static func inside(_ p: StrokeSample, _ r: SnapRect) -> Bool {
        p.x > r.x + 0.001 && p.x < r.maxX - 0.001 && p.y > r.y + 0.001 && p.y < r.maxY - 0.001
    }
    private static func clear(_ a: StrokeSample, _ b: StrokeSample, _ obstacles: [SnapRect]) -> Bool {
        for r in obstacles {
            if abs(a.x - b.x) < 0.001 {
                if a.x > r.x + 0.001, a.x < r.maxX - 0.001, max(a.y, b.y) > r.y + 0.001, min(a.y, b.y) < r.maxY - 0.001 { return false }
            } else if a.y > r.y + 0.001, a.y < r.maxY - 0.001, max(a.x, b.x) > r.x + 0.001, min(a.x, b.x) < r.maxX - 0.001 { return false }
        }
        return true
    }
    private static func route(_ a: StrokeSample, _ b: StrokeSample, obstacles: [SnapRect]) -> [StrokeSample] {
        var xs = [a.x, b.x], ys = [a.y, b.y]
        for box in obstacles { xs += [box.x - 12, box.maxX + 12]; ys += [box.y - 12, box.maxY + 12] }
        xs = Array(Set(xs)).sorted(); ys = Array(Set(ys)).sorted()
        var nodes: [StrokeSample] = []
        for x in xs { for y in ys {
            let p = StrokeSample(x: x, y: y)
            if p == a || p == b || !obstacles.contains(where: { inside(p, $0) }) { nodes.append(p) }
        } }
        guard let start = nodes.firstIndex(of: a), let end = nodes.firstIndex(of: b) else { return [a, b] }
        let count = nodes.count * 3
        var costs = Array(repeating: Double.infinity, count: count), previous = Array(repeating: -1, count: count)
        var visited = Array(repeating: false, count: count)
        costs[start * 3] = 0
        var finished: Int?
        for _ in 0..<count {
            var best = -1, cost = Double.infinity
            for state in 0..<count where !visited[state] && costs[state] < cost { best = state; cost = costs[state] }
            guard best >= 0 else { break }
            visited[best] = true
            let index = best / 3, direction = best % 3
            if index == end { finished = best; break }
            let at = nodes[index]
            for next in nodes.indices where next != index {
                let target = nodes[next]
                guard abs(at.x - target.x) < 0.001 || abs(at.y - target.y) < 0.001, clear(at, target, obstacles) else { continue }
                let nextDirection = abs(at.x - target.x) < 0.001 ? 2 : 1, state = next * 3 + nextDirection
                let distance = abs(at.x - target.x) + abs(at.y - target.y)
                let penalty = direction != 0 && direction != nextDirection ? 12.0 : 0
                let value = cost + distance + penalty
                if value < costs[state] { costs[state] = value; previous[state] = best }
            }
        }
        guard var state = finished else { return [a, .init(x: b.x, y: a.y), b] }
        var result: [StrokeSample] = []
        for _ in 0..<count { result.append(nodes[state / 3]); if previous[state] < 0 { break }; state = previous[state] }
        return Array(result.reversed())
    }
}
