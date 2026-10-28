import Foundation

public enum ShapeArcEditing {
    /// Refit through the dragged midpoint while preserving both chord endpoints.
    public static func curved(_ source: ShapeElement, through point: StrokeSample) -> ShapeElement {
        let positions = ShapeHandles.positions(source, zoom: 1)
        guard let a = positions.first(where: { $0.0 == .start })?.1,
              let b = positions.first(where: { $0.0 == .end })?.1 else { return source }
        let ux = b.x - a.x, uy = b.y - a.y, vx = point.x - a.x, vy = point.y - a.y
        let determinant = 2 * (ux * vy - uy * vx)
        guard abs(determinant) > 0.001 else { return source }
        let u2 = ux * ux + uy * uy, v2 = vx * vx + vy * vy
        let center = StrokeSample(x: a.x + (vy * u2 - uy * v2) / determinant,
                                  y: a.y + (ux * v2 - vx * u2) / determinant)
        let radius = hypot(a.x - center.x, a.y - center.y)
        guard radius.isFinite, radius >= 4, radius <= 10000 else { return source }
        let start = atan2(a.y - center.y, a.x - center.x), end = atan2(b.y - center.y, b.x - center.x)
        let middle = atan2(point.y - center.y, point.x - center.x)
        func positive(_ value: Double) -> Double { let result = value.truncatingRemainder(dividingBy: 2 * .pi); return result < 0 ? result + 2 * .pi : result }
        var sweep = positive(end - start)
        if positive(middle - start) > sweep { sweep -= 2 * .pi }
        guard (10 * Double.pi / 180...350 * Double.pi / 180).contains(abs(sweep)) else { return source }
        var shape = source
        shape.x = center.x - radius; shape.y = center.y - radius; shape.width = radius * 2; shape.height = radius * 2
        shape.rotation = nil; shape.arcStart = start; shape.arcSweep = sweep
        return shape
    }
}
