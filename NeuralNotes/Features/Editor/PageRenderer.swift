import UIKit
import CoreGraphics
import NeuralNotesCore

@MainActor
enum PageRenderer {
    static func draw(_ page: PageSnapshot, package: URL, in context: CGContext, hidingTextID: UUID? = nil, hidingObjectID: UUID? = nil, hidingObjectIDs: Set<UUID> = []) {
        let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let appearance = page.appearance ?? PaperAppearance(spacing: page.paper == .ruled ? 32 : 24)
        let rgb = appearance.tone.rgb
        let paperColor = page.pdfFile == nil ? UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) : UIColor.white
        context.setFillColor(paperColor.cgColor); context.fill(rect)
        if let file = page.pdfFile, let index = page.pdfIndex,
           let document = DocumentRenderCache.shared.pdf(package.appendingPathComponent(file)),
           index >= 0, index < document.numberOfPages,
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
        let objects = ObjectLookup(page), above = Set(page.aboveInkObjects ?? [])
        for id in page.orderedObjectIDs where !above.contains(id) && id != hidingObjectID && !hidingObjectIDs.contains(id) {
            drawObject(id, objects: objects, page: page, package: package, context: context, hidingTextID: hidingTextID)
        }
    }
    /// One object alone, for the picture that follows the finger while it is dragged.
    static func drawSingle(_ id: UUID, page: PageSnapshot, package: URL, in context: CGContext) {
        drawObject(id, objects: ObjectLookup(page), page: page, package: package, context: context, hidingTextID: nil)
    }
    static func drawForeground(_ page: PageSnapshot, package: URL, in context: CGContext, hidingTextID: UUID? = nil, hidingObjectID: UUID? = nil, hidingObjectIDs: Set<UUID> = []) {
        let objects = ObjectLookup(page), above = Set(page.aboveInkObjects ?? [])
        for id in page.orderedObjectIDs where above.contains(id) && id != hidingObjectID && !hidingObjectIDs.contains(id) {
            drawObject(id, objects: objects, page: page, package: package, context: context, hidingTextID: hidingTextID)
        }
        for tape in page.tapes ?? [] {
            let box = CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height)
            context.saveGState()
            if tape.revealed {
                context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.5).cgColor); context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 3]); context.stroke(box)
            } else {
                context.setFillColor(UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1).cgColor)
                context.fill(box)
                ("Tocca per scoprire" as NSString).draw(in: box.insetBy(dx: 8, dy: 5), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray])
            }
            context.restoreGState()
        }
    }
    @MainActor private struct ObjectLookup {
        let texts: [UUID: TextElement], images: [UUID: ImageElement], shapes: [UUID: ShapeElement]
        let connectors: [UUID: ConnectorElement], diagramObjects: [UUID: ConnectorObject]
        init(_ page: PageSnapshot) {
            texts = Dictionary(page.texts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            images = Dictionary(page.images.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            shapes = Dictionary((page.shapes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            connectors = Dictionary((page.connectors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            diagramObjects = connectors.isEmpty ? [:] : DiagramObjects.make(page)
        }
    }
    private static func drawObject(_ id: UUID, objects: ObjectLookup, page: PageSnapshot, package: URL, context: CGContext, hidingTextID: UUID?) {
        if let image = objects.images[id] { ElementRendering.drawImage(image, package: package, context: context) }
        else if let shape = objects.shapes[id] { ElementRendering.drawShape(shape, context: context, page: page) }
        else if let connector = objects.connectors[id] { ConnectorRendering.draw(connector, objects: objects.diagramObjects, page: page, context: context) }
        else if let text = objects.texts[id] {
            if text.lensNote?.isCollapsed == true { drawLensBadge(text, context: context); return }
            let tone = page.appearance?.tone ?? .white
            let value = RichText.attributed(text, color: text.background != nil ? .black : tone == .slate && page.pdfFile == nil ? .white : .black)
            let box = RichText.bounds(text, pageHeight: page.height)
            context.saveGState(); context.translateBy(x: box.midX, y: box.midY)
            context.rotate(by: CGFloat(text.rotation ?? 0) * .pi / 180)
            let local = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)
            if let color = text.background {
                context.setFillColor(UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).cgColor)
                context.addPath(UIBezierPath(roundedRect: local.insetBy(dx: -8, dy: -8), cornerRadius: 6).cgPath); context.fillPath()
            }
            if id != hidingTextID { value.draw(in: local) }
            context.restoreGState()
        }
    }
    /// A Lens note reduced to its icon: a small sticky square with 💡.
    private static func drawLensBadge(_ text: TextElement, context: CGContext) {
        let box = LensNotes.badge(x: text.x, y: text.y), color = text.background ?? InkColor(1, 0.94, 0.55)
        let shape = UIBezierPath(roundedRect: box, cornerRadius: 8).cgPath
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        context.setFillColor(UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).cgColor)
        context.addPath(shape); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.8).cgColor); context.setLineWidth(1)
        context.addPath(shape); context.strokePath()
        let glyph = NSAttributedString(string: "💡", attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let size = glyph.size()
        glyph.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        context.restoreGState()
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
    var hiddenTextID: UUID? { didSet { if oldValue != hiddenTextID { refreshContent() } } }
    /// The object being dragged: only its moving picture is shown until it is dropped.
    var hiddenObjectID: UUID? { didSet { if oldValue != hiddenObjectID { refreshContent() } } }
    var replayHiddenObjectIDs: Set<UUID> = [] { didSet { if oldValue != replayHiddenObjectIDs { refreshContent() } } }
    var interactionHiddenObjectIDs: Set<UUID> = [] { didSet { if oldValue != interactionHiddenObjectIDs { refreshContent() } } }
    private func refreshContent() { setNeedsDisplay(); (superview as? CanvasHost)?.markerReadability.setNeedsDisplay() }
    var allHiddenObjectIDs: Set<UUID> { replayHiddenObjectIDs.union(interactionHiddenObjectIDs) }
    var page = PageSnapshot() {
        didSet {
            if oldValue.id != page.id { layer.contents = nil }
            if oldValue.id != page.id || oldValue.paper != page.paper || oldValue.texts != page.texts
                || oldValue.images != page.images || oldValue.shapes != page.shapes || oldValue.connectors != page.connectors || oldValue.pdfFile != page.pdfFile
                || oldValue.pdfMarkups != page.pdfMarkups || oldValue.appearance != page.appearance || oldValue.width != page.width || oldValue.height != page.height {
                setNeedsDisplay()
            }
        }
    }
    var package = URL(fileURLWithPath: "/")
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PageRenderer.draw(page, package: package, in: context, hidingTextID: hiddenTextID, hidingObjectID: hiddenObjectID, hidingObjectIDs: allHiddenObjectIDs)
    }
}
