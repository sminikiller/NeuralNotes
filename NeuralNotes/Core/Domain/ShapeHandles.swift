import Foundation

public enum ShapeHandle: Hashable, Sendable {
    case corner(Int), rotation, start, end, innerRadius, arcCurvature, vertex(Int)
    public var title: String {
        switch self {
        case .corner(let n): return "Ridimensiona angolo \(n + 1)"
        case .rotation: return "Ruota forma"; case .start: return "Estremo iniziale"; case .end: return "Estremo finale"
        case .innerRadius: return "Raggio interno stella"; case .arcCurvature: return "Curvatura arco"
        case .vertex(let n): return "Vertice \(n + 1)"
        }
    }
}
public enum ShapeHandles {
    public static func positions(_ shape: ShapeElement, zoom: Double) -> [(ShapeHandle, StrokeSample)] {
        let x = shape.x, y = shape.y, w = shape.width, h = shape.height
        var values: [(ShapeHandle, StrokeSample)] = []
        if shape.kind == .line || shape.kind == .arrow {
            let a = shape.start ?? .init(x: 0, y: 1), b = shape.end ?? .init(x: 1, y: 0)
            values = [(.start, .init(x: x + w * a.x, y: y + h * a.y)), (.end, .init(x: x + w * b.x, y: y + h * b.y))]
        } else if shape.kind == .freePolygon {
            let points = shape.vertices ?? [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)]
            values = points.enumerated().map { (.vertex($0.offset), .init(x: x + $0.element.x * w, y: y + $0.element.y * h)) }
        } else {
            values = [(.corner(0), .init(x: x, y: y)), (.corner(1), .init(x: x + w, y: y)),
                      (.corner(2), .init(x: x + w, y: y + h)), (.corner(3), .init(x: x, y: y + h))]
        }
        if shape.kind == .star {
            let angle = .pi / Double(shape.sides ?? 5) - Double.pi / 2, ratio = shape.innerRatio ?? 0.5
            let radius = min(w, h) / 2 * ratio
            values.append((.innerRadius, .init(x: x + w / 2 + radius * cos(angle), y: y + h / 2 + radius * sin(angle))))
        }
        if shape.kind == .arc {
            let start = shape.arcStart ?? 0, sweep = shape.arcSweep ?? .pi
            func at(_ angle: Double) -> StrokeSample { .init(x: x + w / 2 * (1 + cos(angle)), y: y + h / 2 * (1 + sin(angle))) }
            values += [(.start, at(start)), (.end, at(start + sweep)), (.arcCurvature, at(start + sweep / 2))]
        }
        values.append((.rotation, .init(x: x + w / 2, y: y - 32 / max(0.05, zoom))))
        return values.map { ($0.0, ShapeGeometry.rotate($0.1, shape: shape)) }
    }
    public static func moved(_ source: ShapeElement, handle: ShapeHandle, to target: StrokeSample) -> ShapeElement {
        guard target.x.isFinite, target.y.isFinite, abs(target.x) <= 1_000_000, abs(target.y) <= 1_000_000 else { return source }
        var shape = source
        let point = ShapeGeometry.rotate(target, shape: source, inverse: true)
        let cx = source.x + source.width / 2, cy = source.y + source.height / 2
        switch handle {
        case .rotation:
            let angle = atan2(target.y - cy, target.x - cx) * 180 / .pi + 90
            shape.rotation = ShapeRecognitionMath.snappedAngle(angle)
        case .corner(let index):
            guard (0..<4).contains(index) else { return source }
            let corners = [StrokeSample(x: source.x, y: source.y), .init(x: source.x + source.width, y: source.y),
                           .init(x: source.x + source.width, y: source.y + source.height), .init(x: source.x, y: source.y + source.height)]
            let opposite = corners[(index + 2) % 4]
            var newWidth = min(20000, max(8, abs(point.x - opposite.x))), newHeight = min(20000, max(8, abs(point.y - opposite.y)))
            if [.arc, .polygon, .star].contains(source.kind) {
                let side = max(newWidth, newHeight); newWidth = side; newHeight = side
            }
            let adjusted = StrokeSample(x: opposite.x + (point.x < opposite.x ? -newWidth : newWidth),
                                        y: opposite.y + (point.y < opposite.y ? -newHeight : newHeight))
            let localCenter = StrokeSample(x: (adjusted.x + opposite.x) / 2, y: (adjusted.y + opposite.y) / 2)
            let center = ShapeGeometry.rotate(localCenter, shape: source)
            shape.x = center.x - newWidth / 2; shape.y = center.y - newHeight / 2
            shape.width = newWidth; shape.height = newHeight
        case .innerRadius:
            let ratio = hypot(point.x - cx, point.y - cy) / max(1, min(source.width, source.height) / 2)
            shape.innerRatio = min(0.8, max(0.2, ratio))
        case .start, .end:
            if source.kind == .arc {
                let angle = atan2((point.y - cy) / source.height, (point.x - cx) / source.width)
                let sign = (source.arcSweep ?? .pi) >= 0 ? 1.0 : -1.0
                let end = (source.arcStart ?? 0) + (source.arcSweep ?? .pi)
                let start = handle == .start ? angle : (source.arcStart ?? 0)
                var sweep = (handle == .start ? end : angle) - start
                while sweep * sign < 0 { sweep += sign * 2 * .pi }
                shape.arcStart = start
                shape.arcSweep = sign * min(350 * .pi / 180, max(10 * .pi / 180, abs(sweep)))
            } else {
                let positions = positions(source, zoom: 1)
                let otherHandle: ShapeHandle = handle == .start ? .end : .start
                if let other = positions.first(where: { $0.0 == otherHandle })?.1 {
                    let a = handle == .start ? target : other, b = handle == .end ? target : other
                    if let dragged = ShapeElement.dragged(kind: source.kind, from: a, to: b, color: InkColor(source.red, source.green, source.blue), lineWidth: source.lineWidth) {
                        shape.x = dragged.x; shape.y = dragged.y; shape.width = dragged.width; shape.height = dragged.height
                        shape.start = dragged.start; shape.end = dragged.end; shape.rotation = nil
                    }
                }
            }
        case .arcCurvature:
            shape = ShapeArcEditing.curved(source, through: target)
        case .vertex(let index):
            var vertices = source.vertices ?? [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)]
            guard vertices.indices.contains(index) else { return source }
            var local = vertices.map { StrokeSample(x: source.x + $0.x * source.width, y: source.y + $0.y * source.height) }
            local[index] = point
            let left = local.map(\.x).min()!, top = local.map(\.y).min()!
            let width = local.map(\.x).max()! - left, height = local.map(\.y).max()! - top
            guard width >= 1, height >= 1, width <= 20000, height <= 20000 else { return source }
            vertices = local.map { .init(x: ($0.x - left) / width, y: ($0.y - top) / height) }
            guard Set(vertices.map { "\($0.x)|\($0.y)" }).count == vertices.count else { return source }
            let center = ShapeGeometry.rotate(.init(x: left + width / 2, y: top + height / 2), shape: source)
            shape.x = center.x - width / 2; shape.y = center.y - height / 2
            shape.width = width; shape.height = height; shape.vertices = vertices
        }
        if let radius = shape.cornerRadius { shape.cornerRadius = min(radius, min(shape.width, shape.height) / 2) }
        return shape
    }
}
