import UIKit
import PencilKit

/// A vector reconstruction of stroke geometry. PencilKit does not expose its
/// textured brush renderer as PDF paths; the native drawing remains authoritative.
@MainActor
enum VectorInkRenderer {
    static func draw(_ drawing: PKDrawing, in context: CGContext) {
        for stroke in drawing.strokes {
            let points = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
            guard !points.isEmpty else { continue }
            context.saveGState()
            context.concatenate(stroke.transform)
            if let mask = stroke.mask { context.addPath(mask.cgPath); context.clip(using: mask.usesEvenOddFillRule ? .evenOdd : .winding) }
            let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let opacity = points.map(\.opacity).reduce(CGFloat(0), +) / CGFloat(points.count)
            context.setBlendMode(stroke.ink.inkType == .marker ? .multiply : .normal)
            context.setAlpha(min(1, max(0, color.cgColor.alpha * opacity)))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setAlpha(1); context.setFillColor(color.withAlphaComponent(1).cgColor)
            for point in points {
                let size = point.size
                context.fillEllipse(in: CGRect(x: point.location.x - size.width / 2, y: point.location.y - size.height / 2,
                    width: max(0.1, size.width), height: max(0.1, size.height)))
            }
            for (a, b) in zip(points, points.dropFirst()) {
                let angle = atan2(b.location.y - a.location.y, b.location.x - a.location.x)
                let nx = -sin(angle), ny = cos(angle)
                let ar = max(0.05, a.size.width / 2), br = max(0.05, b.size.width / 2)
                context.beginPath()
                context.move(to: CGPoint(x: a.location.x + nx * ar, y: a.location.y + ny * ar))
                context.addLine(to: CGPoint(x: b.location.x + nx * br, y: b.location.y + ny * br))
                context.addLine(to: CGPoint(x: b.location.x - nx * br, y: b.location.y - ny * br))
                context.addLine(to: CGPoint(x: a.location.x - nx * ar, y: a.location.y - ny * ar))
                context.closePath(); context.fillPath()
            }
            context.endTransparencyLayer(); context.restoreGState()
        }
    }
}
