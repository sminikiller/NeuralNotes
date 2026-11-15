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
    private var region = CGRect.zero
    private let composition = MarkerCompositionCache()
    init() {
        super.init(frame: .zero); isUserInteractionEnabled = false; isOpaque = false; backgroundColor = .clear; isHidden = true
        NotificationCenter.default.addObserver(self, selector: #selector(nnPDFMarkerDetailReady(_:)), name: PDFRasterCache.didRender, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func nnPDFMarkerDetailReady(_ note: Notification) {
        guard let host, let page, !isHidden else { return }
        if PDFRasterCache.affects(note, page: page, package: host.surface.package) { setNeedsDisplay() }
    }
    func reset() { region = .zero; page = nil; generation = nil; patches = []; drawing = PKDrawing(); composition.clear(); layer.contents = nil; isHidden = true }
    func update(_ host: CanvasHost?, forceInk: Bool = false) {
        guard let host, let model = host.model else { reset(); return }
        guard model.page?.layers == nil else { if !isHidden || page != nil { reset() }; return }
        self.host = host
        let visible = host.surface.frame.intersection(host.bounds)
        guard !visible.isNull, !visible.isEmpty, model.audio?.replayInk != true || model.audio?.playingSessionID == nil,
              host.canvas.layer.opacity > 0 else { isHidden = true; return }
        let nextZoom = max(0.05, host.canvas.zoomScale)
        let at = CGPoint(x: (visible.minX - host.surface.frame.minX) / nextZoom, y: (visible.minY - host.surface.frame.minY) / nextZoom)
        let inkChanged = forceInk || generation != model.inkDisplayGeneration || page?.id != model.page?.id
        let viewport = CGRect(origin: at, size: CGSize(width: visible.width / nextZoom, height: visible.height / nextZoom))
        let changed = inkChanged || page != host.surface.page || !region.contains(viewport) || zoom != nextZoom
        if inkChanged {
            drawing = host.canvas.drawing
            patches = drawing.strokes.filter { $0.ink.inkType == .marker }.map { $0.renderBounds.insetBy(dx: -2, dy: -2) }
            generation = model.inkDisplayGeneration
        }
        page = host.surface.page
        isHidden = patches.isEmpty
        guard !isHidden else { layer.contents = nil; return }
        if changed {
            region = viewport.insetBy(dx: -128 / nextZoom, dy: -128 / nextZoom)
                .intersection(CGRect(x: 0, y: 0, width: host.surface.page.width, height: host.surface.page.height))
        }
        zoom = nextZoom; origin = region.origin
        frame = CGRect(x: host.surface.frame.minX + region.minX * zoom, y: host.surface.frame.minY + region.minY * zoom,
            width: region.width * zoom, height: region.height * zoom)
        let budget = sqrt(8_000_000 / max(1, bounds.width * bounds.height))
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
                hiddenTextID: host.surface.hiddenTextID, in: context, pdfMode: .interactive)
            return
        }
        composition.draw(page: page, baseline: baseDrawing, token: appendOnly ? model.inkGestureGeneration : model.inkDisplayGeneration,
            delta: delta, package: host.surface.package, bounds: visible, scale: max(0.1, contentScaleFactor * zoom),
            hiddenIDs: hiddenIDs, hiddenTextID: host.surface.hiddenTextID, in: context, pdfMode: .interactive)
    }
}
