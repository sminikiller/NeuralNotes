import Foundation

public enum ShapePathCommand: Equatable, Sendable {
    case move(StrokeSample), line(StrokeSample)
    case quad(StrokeSample, StrokeSample)
    case cubic(StrokeSample, StrokeSample, StrokeSample)
    case close
}
public struct ShapePath: Equatable, Sendable {
    public var commands: [ShapePathCommand]
    public init(_ commands: [ShapePathCommand] = []) { self.commands = commands }
}

/// All coordinates are unzoomed page points. Rotation is already in the path.
/// Rendering, selection, native ink and vector PDF export share this geometry.
public enum ShapeGeometry {
    public static func path(for shape: ShapeElement) -> ShapePath {
        guard [shape.x, shape.y, shape.width, shape.height].allSatisfy(\.isFinite),
              shape.width > 0, shape.height > 0, shape.width <= 20000, shape.height <= 20000,
              abs(shape.x) < 1_000_000, abs(shape.y) < 1_000_000, shape.hasValidOptions else { return ShapePath() }
        let x = shape.x, y = shape.y, w = shape.width, h = shape.height
        var result = ShapePath()
        switch shape.kind {
        case .line, .arrow:
            let a = shape.start ?? ShapeEndpoint(x: 0, y: 1)
            let b = shape.end ?? ShapeEndpoint(x: 1, y: 0)
            result.commands = [.move(point(a, shape)), .line(point(b, shape))]
        case .ellipse:
            result = ellipseArc(shape, start: 0, sweep: 2 * .pi, closed: true)
        case .arc:
            result = ellipseArc(shape, start: shape.arcStart ?? 0, sweep: shape.arcSweep ?? .pi, closed: false)
        case .rectangle:
            result = polygon([sample(x, y), sample(x + w, y), sample(x + w, y + h), sample(x, y + h)], radius: shape.cornerRadius ?? 0)
        case .diamond:
            result = polygon([sample(x + w / 2, y), sample(x + w, y + h / 2), sample(x + w / 2, y + h), sample(x, y + h / 2)], radius: shape.cornerRadius ?? 0)
        case .triangle:
            let points = shape.vertices?.map { point($0, shape) } ?? [sample(x + w / 2, y), sample(x + w, y + h), sample(x, y + h)]
            result = polygon(points, radius: 0)
        case .polygon:
            result = polygon(regularVertices(sides: min(12, max(3, shape.sides ?? 6)), innerRatio: nil, shape: shape), radius: 0)
        case .freePolygon:
            let vertices = shape.vertices ?? [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)]
            result = polygon(vertices.map { point($0, shape) }, radius: 0)
        case .star:
            result = polygon(regularVertices(sides: min(12, max(4, shape.sides ?? 5)), innerRatio: min(0.8, max(0.2, shape.innerRatio ?? 0.5)), shape: shape), radius: 0)
        }
        return rotated(result, shape: shape)
    }
    public static func arrowPaths(for shape: ShapeElement) -> [ShapePath] {
        guard shape.kind.isOpen else { return [] }
        let heads = shape.arrowHeads ?? (shape.kind == .arrow ? .end : .none)
        guard heads != .none, let line = polylines(path(for: shape), steps: 32).first, line.count > 1 else { return [] }
        let length = max(12, shape.lineWidth * 4)
        func head(tip: StrokeSample, neighbor: StrokeSample) -> ShapePath {
            let angle = atan2(tip.y - neighbor.y, tip.x - neighbor.x)
            let a = sample(tip.x - length * cos(angle - .pi / 6), tip.y - length * sin(angle - .pi / 6))
            let b = sample(tip.x - length * cos(angle + .pi / 6), tip.y - length * sin(angle + .pi / 6))
            if shape.arrowStyle == .filled { return ShapePath([.move(tip), .line(a), .line(b), .close]) }
            return ShapePath([.move(a), .line(tip), .line(b)])
        }
        var result: [ShapePath] = []
        if heads == .start || heads == .both { result.append(head(tip: line[0], neighbor: line[1])) }
        if heads == .end || heads == .both { result.append(head(tip: line[line.count - 1], neighbor: line[line.count - 2])) }
        return result
    }
    public static func rotate(_ point: StrokeSample, shape: ShapeElement, inverse: Bool = false) -> StrokeSample {
        let angle = (shape.rotation ?? 0) * .pi / 180 * (inverse ? -1 : 1)
        let cx = shape.x + shape.width / 2, cy = shape.y + shape.height / 2
        let dx = point.x - cx, dy = point.y - cy
        return sample(cx + dx * cos(angle) - dy * sin(angle), cy + dx * sin(angle) + dy * cos(angle))
    }
    public static func regularVertices(sides: Int, innerRatio: Double?, shape: ShapeElement) -> [StrokeSample] {
        let count = innerRatio == nil ? sides : sides * 2
        return (0..<count).map { index in
            let alignment = shape.kind == .polygon ? Double.pi / Double(sides) : 0
            let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2 - alignment
            let ratio = index % 2 == 1 ? (innerRatio ?? 1) : 1
            let radius = min(shape.width, shape.height) / 2 * ratio
            return sample(shape.x + shape.width / 2 + radius * cos(angle),
                          shape.y + shape.height / 2 + radius * sin(angle))
        }
    }
    static func sample(_ x: Double, _ y: Double) -> StrokeSample { StrokeSample(x: x, y: y) }
    private static func point(_ value: ShapeEndpoint, _ shape: ShapeElement) -> StrokeSample {
        sample(shape.x + value.x * shape.width, shape.y + value.y * shape.height)
    }
    private static func polygon(_ points: [StrokeSample], radius: Double) -> ShapePath {
        guard let first = points.first, points.count >= 3 else { return ShapePath() }
        guard radius > 0 else {
            var commands: [ShapePathCommand] = [.move(first)]
            for point in points.dropFirst() { commands.append(.line(point)) }
            commands.append(.close); return ShapePath(commands)
        }
        var commands: [ShapePathCommand] = []
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count], at = points[index], next = points[(index + 1) % points.count]
            let a = hypot(previous.x - at.x, previous.y - at.y), b = hypot(next.x - at.x, next.y - at.y)
            let distance = min(radius, min(a, b) * 0.45)
            let enter = sample(at.x + (previous.x - at.x) * distance / max(0.001, a), at.y + (previous.y - at.y) * distance / max(0.001, a))
            let exit = sample(at.x + (next.x - at.x) * distance / max(0.001, b), at.y + (next.y - at.y) * distance / max(0.001, b))
            commands.append(index == 0 ? .move(enter) : .line(enter)); commands.append(.quad(at, exit))
        }
        commands.append(.close); return ShapePath(commands)
    }
    private static func ellipseArc(_ shape: ShapeElement, start: Double, sweep: Double, closed: Bool) -> ShapePath {
        let count = max(1, min(8, Int(ceil(abs(sweep) / (.pi / 2)))))
        let step = sweep / Double(count), rx = shape.width / 2, ry = shape.height / 2
        let cx = shape.x + rx, cy = shape.y + ry
        func at(_ angle: Double) -> StrokeSample { sample(cx + rx * cos(angle), cy + ry * sin(angle)) }
        var commands: [ShapePathCommand] = [.move(at(start))]
        for index in 0..<count {
            let a = start + Double(index) * step, b = a + step, k = 4 / 3.0 * tan(step / 4)
            let p = at(a), q = at(b)
            let c1 = sample(p.x - k * rx * sin(a), p.y + k * ry * cos(a))
            let c2 = sample(q.x + k * rx * sin(b), q.y - k * ry * cos(b))
            commands.append(.cubic(c1, c2, q))
        }
        if closed { commands.append(.close) }
        return ShapePath(commands)
    }
    private static func rotated(_ path: ShapePath, shape: ShapeElement) -> ShapePath {
        ShapePath(path.commands.map { command in
            switch command {
            case .move(let p): return .move(rotate(p, shape: shape))
            case .line(let p): return .line(rotate(p, shape: shape))
            case .quad(let c, let p): return .quad(rotate(c, shape: shape), rotate(p, shape: shape))
            case .cubic(let a, let b, let p): return .cubic(rotate(a, shape: shape), rotate(b, shape: shape), rotate(p, shape: shape))
            case .close: return .close
            }
        })
    }
}
