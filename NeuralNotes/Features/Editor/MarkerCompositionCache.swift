import UIKit
import PencilKit
import NeuralNotesCore

/// At most two viewport images, two million pixels each. Reused for all the
/// samples of a pen/marker stroke: a PDF is never redrawn per pointer sample.
@MainActor
final class MarkerCompositionCache {
    private var token: UUID?
    private var page: PageSnapshot?
    private var bounds = CGRect.zero
    private var scale: CGFloat = 1
    private var hiddenIDs = Set<UUID>()
    private var hiddenTextID: UUID?
    private var base: UIImage?
    private var pens: UIImage?
    private(set) var builds = 0
    func clear() { token = nil; page = nil; base = nil; pens = nil }
    /// Object/markup erasure also changes the document. Cache only immutable
    /// paper/PDF pixels, then draw the current objects and ink over that base.
    func drawReplacingContent(page: PageSnapshot, drawing: PKDrawing, token: UUID, package: URL,
                              bounds: CGRect, scale: CGFloat, hiddenIDs: Set<UUID>, hiddenTextID: UUID?, in context: CGContext) {
        var paper = PageSnapshot(id: page.id)
        paper.width = page.width; paper.height = page.height; paper.paper = page.paper; paper.appearance = page.appearance
        paper.pdfFile = page.pdfFile; paper.pdfIndex = page.pdfIndex
        draw(page: paper, baseline: PKDrawing(), token: token, delta: PKDrawing(), package: package,
            bounds: bounds, scale: scale, hiddenIDs: [], hiddenTextID: nil, in: context)
        PageRenderer.drawMarkups((page.pdfMarkups ?? []).filter { $0.wordHighlight != true }, in: context)
        var ids = Set(page.objectIDs).subtracting(hiddenIDs)
        if let hiddenTextID { ids.remove(hiddenTextID) }
        PageRenderer.drawSelected(ids, foreground: false, page: page, package: package, in: context)
        PageRenderer.drawMarkups((page.pdfMarkups ?? []).filter { $0.wordHighlight == true }, in: context)
        LegibleInkRenderer.draw(drawing, in: context, bounds: bounds, scale: scale)
    }
    func draw(page: PageSnapshot, baseline: PKDrawing, token: UUID, delta: PKDrawing, package: URL,
              bounds: CGRect, scale: CGFloat, hiddenIDs: Set<UUID>, hiddenTextID: UUID?, in context: CGContext) {
        let limitedScale = max(0.05, min(scale, sqrt(2_000_000 / max(1, bounds.width * bounds.height))))
        if self.token != token || self.page != page || self.bounds != bounds || self.scale != limitedScale || self.hiddenIDs != hiddenIDs || self.hiddenTextID != hiddenTextID {
            self.token = token; self.page = page; self.bounds = bounds; self.scale = limitedScale
            self.hiddenIDs = hiddenIDs; self.hiddenTextID = hiddenTextID; builds += 1
            let format = UIGraphicsImageRendererFormat(); format.scale = limitedScale
            base = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
                let target = renderer.cgContext; target.translateBy(x: -bounds.minX, y: -bounds.minY)
                PageRenderer.draw(page, package: package, in: target, hidingTextID: hiddenTextID, hidingObjectIDs: hiddenIDs)
                LegibleInkRenderer.draw(baseline, in: target, bounds: bounds, scale: limitedScale)
            }
            let ordinary = PKDrawing(strokes: baseline.strokes.filter { $0.ink.inkType != .marker && $0.renderBounds.intersects(bounds) })
            pens = ordinary.strokes.isEmpty ? nil : PaperInk.image(ordinary, from: bounds, scale: limitedScale)
        }
        base?.draw(in: bounds)
        guard !delta.strokes.isEmpty else { return }
        let area = delta.bounds.insetBy(dx: -2, dy: -2).intersection(bounds)
        guard !area.isNull, !area.isEmpty else { return }
        LegibleInkRenderer.draw(delta, in: context, bounds: area, scale: scale)
        if delta.strokes.contains(where: { $0.ink.inkType == .marker }) { pens?.draw(in: bounds) }
    }
}
