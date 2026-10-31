import UIKit
import PencilKit
import NeuralNotesCore

/// Recompose only the visible marker patches with the underlying document.
/// A transparent UIKit view cannot multiply against siblings, so the PDF and
/// ink must share this context. The native canvas keeps receiving all touches.
@MainActor
final class MarkerReadabilityOverlay: UIView {
    private weak var host: CanvasHost?
    private var generation: UUID?
    private var page: PageSnapshot?
    private var drawing = PKDrawing()
    private var patches: [CGRect] = []
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private let composition = MarkerCompositionCache()
    init() { super.init(frame: .zero); isUserInteractionEnabled = false; isOpaque = false; backgroundColor = .clear; isHidden = true }
    required init?(coder: NSCoder) { nil }
    func reset() { page = nil; generation = nil; patches = []; drawing = PKDrawing(); composition.clear(); layer.contents = nil; isHidden = true }
    func update(_ host: CanvasHost?) {
        guard let host, let model = host.model else { reset(); return }
        self.host = host
        let visible = host.surface.frame.intersection(host.bounds)
        guard !visible.isNull, !visible.isEmpty, model.audio?.replayInk != true || model.audio?.playingSessionID == nil,
              host.canvas.layer.opacity > 0 else { isHidden = true; return }
        let nextZoom = max(0.05, host.canvas.zoomScale)
        let at = CGPoint(x: (visible.minX - host.surface.frame.minX) / nextZoom, y: (visible.minY - host.surface.frame.minY) / nextZoom)
        let inkChanged = generation != model.inkDisplayGeneration || page?.id != model.page?.id
        let changed = inkChanged || page != host.surface.page || frame != visible || origin != at || zoom != nextZoom
        if inkChanged {
            drawing = host.canvas.drawing
            patches = drawing.strokes.filter { $0.ink.inkType == .marker }.map { $0.renderBounds.insetBy(dx: -2, dy: -2) }
            generation = model.inkDisplayGeneration
        }
        isHidden = patches.isEmpty
        guard !isHidden else { layer.contents = nil; return }
        page = host.surface.page; frame = visible; zoom = nextZoom; origin = at
        let budget = sqrt(8_000_000 / max(1, visible.width * visible.height))
        contentScaleFactor = min(host.window?.screen.scale ?? UIScreen.main.scale, budget)
        if changed { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
        guard let host, let model = host.model, let page, let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        let visible = CGRect(origin: origin, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        let clipped = patches.compactMap { patch -> CGRect? in
            let box = patch.intersection(visible); return box.isNull || box.isEmpty ? nil : box
        }
        guard !clipped.isEmpty else { return }
        context.addRects(clipped); context.clip()
        let baseline = model.inkGestureBaseline
        let appendOnly = baseline != nil && (model.tool == .pen || model.tool == .marker) && drawing.strokes.count >= (baseline?.strokes.count ?? 0)
        let baseDrawing = appendOnly ? baseline! : drawing
        let delta = appendOnly ? PKDrawing(strokes: Array(drawing.strokes.dropFirst(baseDrawing.strokes.count))) : PKDrawing()
        var hiddenIDs = host.surface.allHiddenObjectIDs
        if let id = host.surface.hiddenObjectID { hiddenIDs.insert(id) }
        if let token = model.eraserCompositionToken {
            composition.drawReplacingContent(page: page, drawing: drawing, token: token, package: host.surface.package,
                bounds: visible, scale: max(0.1, contentScaleFactor * zoom), hiddenIDs: hiddenIDs,
                hiddenTextID: host.surface.hiddenTextID, in: context)
            return
        }
        composition.draw(page: page, baseline: baseDrawing, token: appendOnly ? model.inkGestureGeneration : model.inkDisplayGeneration,
            delta: delta, package: host.surface.package, bounds: visible, scale: max(0.1, contentScaleFactor * zoom),
            hiddenIDs: hiddenIDs, hiddenTextID: host.surface.hiddenTextID, in: context)
    }
}
