import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
final class RectangularMarkerSession {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    private let page: PageSnapshot, before: PKDrawing, color: InkColor, start: CGPoint
    private let preview: LiveMarkerPreview
    private let snap: Bool
    private var rectangles: [CGRect] = []
    init?(host: CanvasHost, model: EditorViewModel, at point: CGPoint) {
        guard model.canEditActiveLayer, let page = model.page else { return nil }
        self.host = host; self.model = model; self.page = page; self.before = model.canvas.drawing
        start = point; color = InkColor(model.ink)
        snap = page.pdfFile != nil && model.writingOptions.rectangleSnapLines == true
        preview = LiveMarkerPreview(host: host, page: page, baseline: before, color: PaperInk.color(model.ink))
        model.strokeBegan(); model.drawingShape = true
    }
    func move(_ points: [CGPoint]) {
        guard let last = points.last else { return }
        let box = CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(last.x - start.x), height: abs(last.y - start.y))
            .intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        rectangles = box.isNull || box.width < 1 || box.height < 1 ? [] : [box]
        if snap, PageWordIndex.shared.isReady(page), let words = PageWordIndex.shared.groups(for: page).first {
            let lines = RectangularMarker.snapped(box, words: words)
            if !lines.isEmpty { rectangles = lines.map { $0.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height)) }.filter { !$0.isNull && !$0.isEmpty } }
        }
        let path = CGMutablePath(); path.addRects(rectangles); preview.update(path: path)
    }
    func finish(cancelled: Bool) {
        defer { host?.synchronizePage(); preview.removeFromSuperview() }
        guard let model, model.page?.id == page.id else { return }
        model.cancelGuidedInk(before)
        guard !cancelled, !rectangles.isEmpty else { return }
        var shapes = rectangles.compactMap { RectangularMarker.make($0, color: color) }
        if let anchor = model.audio?.recordingAnchor {
            for i in shapes.indices { shapes[i].audioAnchor = StrokeAnchor(signature: "shape:\(shapes[i].id)", audioSessionID: anchor.0, seconds: anchor.1) }
        }
        model.mutatePage("Evidenziatore rettangolare") { $0.shapes = ($0.shapes ?? []) + shapes }
        model.selectedIDs = Set(shapes.map(\.id)); model.rememberPalette()
        model.prepareMarkerWords()
    }
}
