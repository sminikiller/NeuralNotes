import Foundation

public enum ConnectorGeometry {
    public static func resolve(_ end: ConnectorEnd, objects: [UUID: ConnectorObject]) -> StrokeSample {
        guard let id = end.objectID, let object = objects[id], object.rect.valid, object.rotation.isFinite, end.anchor.isValid else { return end.point }
        return object.point(at: end.anchor)
    }
    public static func path(_ connector: ConnectorElement, objects: [UUID: ConnectorObject]) -> ShapePath {
        guard connector.isValid else { return ShapePath() }
        let a = resolve(connector.from, objects: objects), b = resolve(connector.to, objects: objects)
        switch connector.routing {
        case .straight: return ShapePath([.move(a), .line(b)])
        case .curved:
            if let controls = connector.controlPoints, controls.count >= 2 { return ShapePath([.move(a), .cubic(controls[0], controls[1], b)]) }
            let dx = b.x - a.x, dy = b.y - a.y, length = max(24, min(300, hypot(dx, dy) * 0.4))
            let unit = StrokeSample(x: dx / max(0.001, hypot(dx, dy)), y: dy / max(0.001, hypot(dx, dy)))
            let n1 = normal(connector.from, at: a, objects: objects, fallback: unit)
            let n2 = normal(connector.to, at: b, objects: objects, fallback: .init(x: -unit.x, y: -unit.y))
            return ShapePath([.move(a), .cubic(offset(a, n1, length), offset(b, n2, length), b)])
        case .elbow: return ConnectorOrthogonal.path(connector, objects: objects)
        }
    }
    public static func bounds(_ connector: ConnectorElement, objects: [UUID: ConnectorObject]) -> SnapRect {
        let paths = [path(connector, objects: objects)] + arrowPaths(connector, objects: objects)
        let points = paths.flatMap { ShapeGeometry.polylines($0).flatMap { $0 } }
        guard let first = points.first else { return .init(x: connector.from.x, y: connector.from.y, width: 1, height: 1) }
        var x0 = first.x, x1 = first.x, y0 = first.y, y1 = first.y
        for p in points { x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y) }
        return .init(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
    }
    public static func arrowPaths(_ connector: ConnectorElement, objects: [UUID: ConnectorObject]) -> [ShapePath] {
        let style = connector.effectiveStyle, heads = style.arrowHeads ?? .end
        guard heads != .none, let line = ShapeGeometry.polylines(path(connector, objects: objects)).first, line.count >= 2 else { return [] }
        let length = max(12, (style.width ?? 2) * 4)
        func head(_ tip: StrokeSample, _ neighbor: StrokeSample) -> ShapePath {
            let angle = atan2(tip.y - neighbor.y, tip.x - neighbor.x)
            let a = StrokeSample(x: tip.x - length * cos(angle - .pi / 6), y: tip.y - length * sin(angle - .pi / 6))
            let b = StrokeSample(x: tip.x - length * cos(angle + .pi / 6), y: tip.y - length * sin(angle + .pi / 6))
            return style.arrowStyle == .filled ? ShapePath([.move(tip), .line(a), .line(b), .close]) : ShapePath([.move(a), .line(tip), .line(b)])
        }
        var result: [ShapePath] = []
        if heads == .start || heads == .both { result.append(head(line[0], line[1])) }
        if heads == .end || heads == .both { result.append(head(line[line.count - 1], line[line.count - 2])) }
        return result
    }
    public static func hit(_ point: StrokeSample, connector: ConnectorElement, objects: [UUID: ConnectorObject], zoom: Double) -> Bool {
        let tolerance = 8 / max(0.05, zoom) + (connector.effectiveStyle.width ?? 2) / 2
        let paths = [path(connector, objects: objects)] + arrowPaths(connector, objects: objects)
        for (index, path) in paths.enumerated() { for line in ShapeGeometry.polylines(path) {
            if index > 0, connector.effectiveStyle.arrowStyle == .filled, ShapeGeometry.contains(point, polygon: line) { return true }
            for i in 1..<line.count where ShapeGeometry.segmentDistance(point, line[i - 1], line[i]) <= tolerance { return true }
        }
        }
        return false
    }
    public static func midpoint(_ connector: ConnectorElement, objects: [UUID: ConnectorObject]) -> StrokeSample {
        let points = ShapeGeometry.polylines(path(connector, objects: objects), steps: 64).flatMap { $0 }
        guard let first = points.first else { return connector.from.point }
        var total = 0.0
        for i in 1..<points.count { total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
        var travelled = 0.0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i], length = hypot(b.x - a.x, b.y - a.y)
            if travelled + length >= total / 2 {
                let t = length > 0 ? (total / 2 - travelled) / length : 0
                return .init(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
            }; travelled += length
        }
        return first
    }
    static func normal(_ end: ConnectorEnd, at p: StrokeSample, objects: [UUID: ConnectorObject], fallback: StrokeSample) -> StrokeSample {
        guard let id = end.objectID, let object = objects[id] else { return fallback }
        return object.normal(at: p)
    }
    static func offset(_ p: StrokeSample, _ n: StrokeSample, _ length: Double) -> StrokeSample { .init(x: p.x + n.x * length, y: p.y + n.y * length) }
}
