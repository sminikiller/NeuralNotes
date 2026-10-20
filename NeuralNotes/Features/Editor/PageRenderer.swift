import UIKit
import CoreGraphics
import NeuralNotesCore

@MainActor
enum PageRenderer {
    static func draw(_ page: PageSnapshot, package: URL, in context: CGContext, hidingTextID: UUID? = nil) {
        let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let appearance = page.appearance ?? PaperAppearance(spacing: page.paper == .ruled ? 32 : 24)
        let rgb = appearance.tone.rgb
        let paperColor = page.pdfFile == nil ? UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) : UIColor.white
        context.setFillColor(paperColor.cgColor); context.fill(rect)
        if let file = page.pdfFile, let index = page.pdfIndex,
           let document = DocumentRenderCache.shared.pdf(package.appendingPathComponent(file)),
           let pdf = document.page(at: index + 1) {
            context.saveGState()
            context.translateBy(x: 0, y: rect.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(pdf.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(pdf); context.restoreGState()
        } else {
            context.setStrokeColor(UIColor(red: 0.65, green: 0.75, blue: 0.78, alpha: 0.5).cgColor)
            context.setFillColor(UIColor(red: 0.55, green: 0.65, blue: 0.68, alpha: 0.55).cgColor)
            context.setLineWidth(0.6)
            let step: CGFloat = CGFloat(appearance.spacing)
            PaperPatternRenderer.draw(page.paper, step: step, in: rect, context: context)
            if appearance.margin {
                context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.45).cgColor)
                context.move(to: CGPoint(x: 64, y: 0)); context.addLine(to: CGPoint(x: 64, y: rect.height)); context.strokePath()
            }
        }
        for markup in page.pdfMarkups ?? [] {
            let box = CGRect(x: markup.x, y: markup.y, width: markup.width, height: markup.height)
            context.saveGState(); context.setBlendMode(.multiply)
            if markup.kind == .highlight { context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.35).cgColor); context.fill(box) }
            else { context.setStrokeColor(UIColor.systemRed.cgColor); context.setLineWidth(1); context.move(to: CGPoint(x: box.minX, y: box.maxY)); context.addLine(to: CGPoint(x: box.maxX, y: box.maxY)); context.strokePath() }
            context.restoreGState()
        }
        for image in page.images {
            ElementRendering.drawImage(image, package: package, context: context)
        }
        for shape in page.shapes ?? [] { ElementRendering.drawShape(shape, context: context) }
        for text in page.texts where text.id != hidingTextID {
            let value = RichText.attributed(text, color: appearance.tone == .slate && page.pdfFile == nil ? .white : .black)
            let size = value.boundingRect(with: CGSize(width: text.width, height: max(0, page.height - text.y)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let box = CGRect(x: text.x, y: text.y, width: text.width, height: max(text.fontSize + 4, size.height))
            context.saveGState(); context.translateBy(x: box.midX, y: box.midY)
            context.rotate(by: CGFloat(text.rotation ?? 0) * .pi / 180)
            value.draw(in: CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height))
            context.restoreGState()
        }
    }
}

@MainActor
final class PageSurfaceView: UIView {
    /// Redraw at the visible zoom resolution, bounded to 32 MB per surface.
    func updateResolution(zoom: CGFloat, screenScale: CGFloat) {
        let maximum = sqrt(8_000_000 / max(1, CGFloat(page.width * page.height)))
        let scale = max(0.5, min(maximum, screenScale * max(1, zoom)))
        guard abs(contentScaleFactor - scale) > 0.15 else { return }
        contentScaleFactor = scale; layer.contentsScale = scale; setNeedsDisplay()
    }
    var hiddenTextID: UUID? { didSet { if oldValue != hiddenTextID { setNeedsDisplay() } } }
    var page = PageSnapshot() {
        didSet {
            if oldValue.id != page.id || oldValue.paper != page.paper || oldValue.texts != page.texts
                || oldValue.images != page.images || oldValue.shapes != page.shapes || oldValue.pdfFile != page.pdfFile
                || oldValue.pdfMarkups != page.pdfMarkups || oldValue.appearance != page.appearance || oldValue.width != page.width || oldValue.height != page.height {
                setNeedsDisplay()
            }
        }
    }
    var package = URL(fileURLWithPath: "/")
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PageRenderer.draw(page, package: package, in: context, hidingTextID: hiddenTextID)
    }
}
