import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum EraserStrokeGeometry {
    static func area(samples: [StrokeSample], width: Double) -> CGPath? {
        guard let first = samples.first, width.isFinite, width > 0,
              samples.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return nil }
        if samples.allSatisfy({ hypot($0.x - first.x, $0.y - first.y) < 0.1 }) {
            return CGPath(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width), transform: nil)
        }
        let path = CGMutablePath(); path.move(to: CGPoint(x: first.x, y: first.y))
        for point in samples.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }
    /// Cached once for each candidate stroke. Varying width and existing masks
    /// are included, so the empty interior of a curve is never an eraser hit.
    static func visible(_ stroke: PKStroke) -> CGPath {
        let transform = stroke.transform, scale = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
        guard scale.isFinite, scale > 0, stroke.ink.color.cgColor.alpha > 0 else { return CGMutablePath() }
        var length: CGFloat = 0, previous: CGPoint?
        for point in stroke.path {
            if let previous { length += hypot(point.location.x - previous.x, point.location.y - previous.y) }
            previous = point.location
        }
        let distance = max(1, length / 12000), outline = CGMutablePath()
        var last: (CGPoint, CGFloat)?, first: (CGPoint, CGFloat)?, segments = 0
        for point in stroke.path.interpolatedPoints(by: .distance(distance)) {
            guard point.opacity > 0.001 else { last = nil; continue }
            let location = point.location.applying(transform), width = max(0.1, max(point.size.width, point.size.height) * scale)
            if first == nil { first = (location, width) }
            if let last {
                let segment = CGMutablePath(); segment.move(to: last.0); segment.addLine(to: location)
                if hypot(location.x - last.0.x, location.y - last.0.y) > 0.001 {
                    outline.addPath(segment.copy(strokingWithWidth: max(width, last.1), lineCap: .round, lineJoin: .round, miterLimit: 1)); segments += 1
                }
            }
            last = (location, width)
        }
        let fallback = stroke.path.first.flatMap { point -> (CGPoint, CGFloat)? in
            guard point.opacity > 0.001 else { return nil }
            return (point.location.applying(transform), max(0.1, max(point.size.width, point.size.height) * scale))
        }
        if segments == 0, let dot = first ?? fallback {
            outline.addEllipse(in: CGRect(x: dot.0.x - dot.1 / 2, y: dot.0.y - dot.1 / 2, width: dot.1, height: dot.1))
        }
        var region = outline.normalized(using: .winding)
        if let mask = stroke.mask {
            var world = transform
            if let clip = mask.cgPath.normalized(using: mask.usesEvenOddFillRule ? .evenOdd : .winding).copy(using: &world) {
                region = region.intersection(clip, using: .winding)
            }
        }
        return region
    }
    /// nil means no visible hit. A hit may remove the whole stroke, or return
    /// the exact surviving native path with a new vector mask and the same seed.
    static func cut(_ stroke: PKStroke, visible: CGPath, area: CGPath, whole: Bool) -> (stroke: PKStroke?, visible: CGPath)? {
        guard visible.boundingBoxOfPath.intersects(area.boundingBoxOfPath), !visible.intersection(area, using: .winding).isEmpty else { return nil }
        if whole { return (nil, CGMutablePath()) }
        let remainingVisible = visible.subtracting(area, using: .winding)
        guard !remainingVisible.isEmpty else { return (nil, remainingVisible) }
        let t = stroke.transform, determinant = t.a * t.d - t.b * t.c
        guard determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
        var inverse = t.inverted()
        guard let localCut = area.copy(using: &inverse) else { return nil }
        let base = stroke.mask.map { $0.cgPath.normalized(using: $0.usesEvenOddFillRule ? .evenOdd : .winding) }
            ?? CGPath(rect: stroke.renderBounds.applying(inverse).insetBy(dx: -2, dy: -2), transform: nil)
        let mask = UIBezierPath(cgPath: base.subtracting(localCut, using: .winding))
        let result = PKStroke(ink: stroke.ink, path: stroke.path, transform: t, mask: mask, randomSeed: stroke.randomSeed)
        return (result, remainingVisible)
    }
}
