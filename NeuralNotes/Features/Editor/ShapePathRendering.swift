import UIKit
import NeuralNotesCore

@MainActor
enum ShapePathRendering {
    static func path(_ value: ShapePath) -> CGPath {
        let result = CGMutablePath()
        func point(_ value: StrokeSample) -> CGPoint { CGPoint(x: value.x, y: value.y) }
        for command in value.commands {
            switch command {
            case .move(let p): result.move(to: point(p))
            case .line(let p): result.addLine(to: point(p))
            case .quad(let c, let p): result.addQuadCurve(to: point(p), control: point(c))
            case .cubic(let a, let b, let p): result.addCurve(to: point(p), control1: point(a), control2: point(b))
            case .close: result.closeSubpath()
            }
        }
        return result
    }
    static func draw(_ shape: ShapeElement, context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        let outline = path(ShapeGeometry.path(for: shape))
        if let fill = shape.fill, !shape.kind.isOpen {
            context.setFillColor(UIColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: shape.fillOpacity ?? 0.25).cgColor)
            context.addPath(outline); context.fillPath()
        }
        let color = UIColor(red: shape.red, green: shape.green, blue: shape.blue, alpha: shape.strokeOpacity ?? 1)
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(shape.lineWidth); context.setLineCap(.round); context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: (shape.dash ?? .solid).lengths(width: shape.lineWidth).map { CGFloat($0) })
        context.addPath(outline); context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        for head in ShapeGeometry.arrowPaths(for: shape) {
            context.addPath(path(head))
            if shape.arrowStyle == .filled { context.drawPath(using: .fillStroke) }
            else { context.strokePath() }
        }
    }
}
