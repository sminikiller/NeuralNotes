import UIKit
import NeuralNotesCore

@MainActor
enum ElementRendering {
    static func drawImage(_ element: ImageElement, package: URL, context: CGContext) {
        guard let image = DocumentRenderCache.shared.croppedImage(package.appendingPathComponent(element.file), crop: element.crop ?? .full,
            perspective: element.perspective, quarterTurns: element.photoQuarterTurns ?? 0, enhanced: element.photoEnhanced ?? false) else { return }
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        let angle = (element.rotation ?? 0).truncatingRemainder(dividingBy: 360)
        context.rotate(by: CGFloat(angle) * .pi / 180)
        let sideways = abs(angle.truncatingRemainder(dividingBy: 180)) == 90
        let size = sideways ? CGSize(width: rect.height, height: rect.width) : rect.size
        image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    static func drawShape(_ shape: ShapeElement, context: CGContext, page: PageSnapshot? = nil) {
        ShapePathRendering.draw(shape, context: context)
        if let label = DiagramLabels.shape(shape, page: page) {
            context.saveGState()
            if !shape.kind.isOpen { context.addPath(ShapePathRendering.path(ShapeGeometry.path(for: shape))); context.clip() }
            DiagramLabels.draw(label, context: context); context.restoreGState()
        }
    }
}
