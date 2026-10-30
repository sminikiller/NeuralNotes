import Foundation

/// A safe unrotated text region. The renderer applies the shape's rotation to
/// both the region and the glyphs, using this same geometry for word selection.
public enum ShapeLabelRegion {
    public static func rect(_ shape: ShapeElement) -> SnapRect {
        let r = SnapRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height)
        guard r.valid else { return .init(x: 0, y: 0, width: 1, height: 1) }
        if shape.kind.isOpen {
            let width = min(280, max(80, r.width))
            return .init(x: r.midX - width / 2, y: r.midY - 24, width: width, height: 48)
        }
        switch shape.kind {
        case .rectangle:
            let desired = max(12, (shape.cornerRadius ?? 0) * 0.3)
            let inset = min(desired, min(r.width, r.height) * 0.4)
            return .init(x: r.x + inset, y: r.y + inset, width: r.width - 2 * inset, height: r.height - 2 * inset)
        case .ellipse: return centered(r, width: r.width * 0.7, height: r.height * 0.7)
        case .diamond: return centered(r, width: r.width * 0.48, height: r.height * 0.48)
        case .triangle where shape.vertices == nil:
            return .init(x: r.x + r.width * 0.3, y: r.y + r.height * 0.42, width: r.width * 0.4, height: r.height * 0.5)
        case .star:
            let side = min(r.width, r.height) * (shape.innerRatio ?? 0.5) * 0.7
            return centered(r, width: side, height: side)
        case .polygon:
            let side = min(r.width, r.height) * cos(.pi / Double(shape.sides ?? 6)) * 0.7
            return centered(r, width: side, height: side)
        default: return interior(shape)
        }
    }
    private static func centered(_ r: SnapRect, width: Double, height: Double) -> SnapRect {
        .init(x: r.midX - width / 2, y: r.midY - height / 2, width: width, height: height)
    }
    private static func interior(_ shape: ShapeElement) -> SnapRect {
        var local = shape; local.rotation = nil
        guard let outline = ShapeGeometry.polylines(ShapeGeometry.path(for: local)).first, outline.count >= 3 else {
            return .init(x: shape.x, y: shape.y, width: 1, height: 1)
        }
        var point = StrokeSample(x: shape.x + shape.width / 2, y: shape.y + shape.height / 2), radius = 0.0
        var candidates: [StrokeSample] = []
        for x in 1...9 { for y in 1...9 {
            candidates.append(.init(x: shape.x + Double(x) * shape.width / 10, y: shape.y + Double(y) * shape.height / 10))
        } }
        // Thin, slanted polygons may fall between all grid samples. Local
        // triangle centroids provide interior candidates without a dense grid.
        if outline.count >= 3 {
            for i in 1..<(outline.count - 1) {
                candidates.append(.init(x: (outline[0].x + outline[i].x + outline[i + 1].x) / 3,
                    y: (outline[0].y + outline[i].y + outline[i + 1].y) / 3))
            }
        }
        for p in candidates {
            guard ShapeGeometry.contains(p, polygon: outline) else { continue }
            var distance = Double.infinity
            for i in 1..<outline.count { distance = min(distance, ShapeGeometry.segmentDistance(p, outline[i - 1], outline[i])) }
            if distance > radius { radius = distance; point = p }
        }
        let side = radius * 1.4
        return .init(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }
}
