import UIKit
import NeuralNotesCore

@MainActor
enum ElementRendering {
    static func drawImage(_ element: ImageElement, package: URL, context: CGContext) {
        guard let image = DocumentRenderCache.shared.image(package.appendingPathComponent(element.file)), let cg = image.cgImage else { return }
        let crop = element.crop ?? .full
        let source = CGRect(x: crop.x * Double(cg.width), y: crop.y * Double(cg.height),
            width: crop.width * Double(cg.width), height: crop.height * Double(cg.height)).integral
        guard let cropped = cg.cropping(to: source) else { return }
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        let angle = element.rotation ?? 0
        context.rotate(by: CGFloat(angle) * .pi / 180)
        let sideways = abs(angle.truncatingRemainder(dividingBy: 180)) == 90
        let size = sideways ? CGSize(width: rect.height, height: rect.width) : rect.size
        UIImage(cgImage: cropped).draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    static func drawShape(_ shape: ShapeElement, context: CGContext) {
        let rect = CGRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(shape.rotation ?? 0) * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        context.setStrokeColor(UIColor(red: shape.red, green: shape.green, blue: shape.blue, alpha: 1).cgColor)
        context.setLineWidth(shape.lineWidth); context.setLineCap(.round); context.setLineJoin(.round)
        switch shape.kind {
        case .ellipse: context.strokeEllipse(in: rect)
        case .rectangle: context.stroke(rect)
        case .line, .arrow:
            let start = shape.start ?? ShapeEndpoint(x: 0, y: 1), end = shape.end ?? ShapeEndpoint(x: 1, y: 0)
            let a = CGPoint(x: rect.minX + CGFloat(start.x) * rect.width, y: rect.minY + CGFloat(start.y) * rect.height)
            let b = CGPoint(x: rect.minX + CGFloat(end.x) * rect.width, y: rect.minY + CGFloat(end.y) * rect.height)
            context.move(to: a); context.addLine(to: b)
            if shape.kind == .arrow {
                let angle = atan2(b.y - a.y, b.x - a.x), length = max(12, shape.lineWidth * 4)
                for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    context.move(to: b); context.addLine(to: CGPoint(x: b.x - length * cos(angle + delta), y: b.y - length * sin(angle + delta)))
                }
            }
            context.strokePath()
        }
        context.restoreGState()
    }
}
