import UIKit
import NeuralNotesCore

@MainActor
enum ElementRendering {
    private static var pdfImageDepth = 0
    static func preservingPDFImages(_ enabled: Bool, _ body: () -> Void) {
        if enabled { pdfImageDepth += 1 }; defer { if enabled { pdfImageDepth -= 1 } }
        body()
    }
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
        let target = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        if pdfImageDepth > 0, let source = image.cgImage {
            // Cropped images are orientation-normalized by DocumentRenderCache.
            // Preserve their original CGImage/profile in a PDF, without UIKit
            // first preparing an image for the context's Generic RGB space.
            context.scaleBy(x: 1, y: -1); context.draw(source, in: target)
        } else { image.draw(in: target) }
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
