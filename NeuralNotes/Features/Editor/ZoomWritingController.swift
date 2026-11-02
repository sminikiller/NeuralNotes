import UIKit
import PencilKit
import Observation
import NeuralNotesCore

@MainActor @Observable
final class ZoomWritingController: NSObject, PKCanvasViewDelegate {
    let model: EditorViewModel
    @ObservationIgnored let host: CanvasHost
    var geometry: ZoomWritingGeometry?
    var automatic = true
    private(set) var nativeStrokeActive = false
    @ObservationIgnored private var ending: Task<Void, Never>?
    @ObservationIgnored private var installing = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private let pageID: UUID?
    @ObservationIgnored private var originalRuler: Bool
    @ObservationIgnored private var originalProtractor: Bool
    @ObservationIgnored private var panelSize = CGSize.zero
    @ObservationIgnored private var copiedGeneration: UUID?
    @ObservationIgnored private var overview: ZoomWritingViewport?
    init(model: EditorViewModel) {
        self.model = model; host = CanvasHost(canvas: PKCanvasView()); pageID = model.page?.id
        originalRuler = model.rulerActive; originalProtractor = model.protractorActive
        super.init()
        host.model = model; host.surface.package = model.workspace.package; host.surface.page = model.page ?? PageSnapshot()
        host.canvas.delegate = self; host.canvas.accessibilityIdentifier = "zoomWritingCanvas"
        host.canvas.accessibilityLabel = "Scrivi nella finestra di zoom"
        host.drawingAssistant = CanvasDrawingAssistant(host: host, model: model)
        host.drawingAssistant?.zoomWritingInput = true
        host.drawingAssistant?.customGestureFinished = { [weak self] in self?.customFinished() }
        model.rulerActive = false; model.protractorActive = false
        model.zoomWritingController = self
        if let parent = model.pagePresenter as? CanvasHost {
            let viewport = ZoomWritingViewport(controller: self, host: parent); overview = viewport; parent.addSubview(viewport)
        }
        syncFromMain(); configureTool()
    }
    var available: Bool { geometry != nil && !closed && model.page?.id == pageID && model.zoomWritingOpen && model.hasLease && !model.loading && !model.navigating }
    func configureTool() {
        guard !closed, !nativeStrokeActive, !model.drawingShape else { return }
        if model.tool != .pen && model.tool != .marker && model.tool != .eraser || model.audio?.replayInk == true {
            finishAndClose(); model.zoomWritingOpen = false; return
        }
        let canvas = host.canvas
        PaperInk.configure(canvas)
        switch model.tool {
        case .pen: canvas.tool = PKInkingTool(model.writingOptions.pen.native, color: PaperInk.color(model.ink), width: model.thickness)
        case .marker: canvas.tool = PKInkingTool(.marker, color: PaperInk.color(model.ink), width: model.markerWidth)
        case .eraser: canvas.tool = PKEraserTool(.bitmap, width: model.writingOptions.eraserWidth)
        default: break
        }
        canvas.drawingGestureRecognizer.isEnabled = available && model.tool == .pen
        canvas.drawingPolicy = model.fingerDrawing ? .anyInput : .pencilOnly
        canvas.panGestureRecognizer.isEnabled = false; canvas.pinchGestureRecognizer?.isEnabled = false
    }
    func resize(_ size: CGSize) {
        guard let page = model.page, size.width > 0, size.height > 0, panelSize != size, !nativeStrokeActive, !model.drawingShape else { return }
        panelSize = size
        if geometry == nil {
            geometry = ZoomWritingGeometry(pageWidth: page.width, pageHeight: page.height, panelWidth: size.width, panelHeight: size.height)
            if let parent = model.pagePresenter as? CanvasHost, let viewport = geometry {
                let center = parent.surface.convert(CGPoint(x: parent.bounds.midX, y: parent.bounds.midY), from: parent)
                geometry?.move(to: .init(x: center.x - viewport.width / 2, y: center.y - viewport.height / 2))
            }
        } else { geometry?.resize(panelWidth: size.width, panelHeight: size.height, zoom: geometry?.zoom ?? 3) }
        updateViewport(); configureTool()
    }
    func refresh() {
        guard geometry != nil else { return }
        guard !closed, model.page?.id == pageID, model.zoomWritingOpen, model.hasLease else { if !closed { finishAndClose() }; return }
        configureTool()
        guard !model.loading, !model.navigating else { return }
        mainDrawingChanged()
        host.surface.page = model.page ?? host.surface.page; host.alignSurface(); overview?.refresh()
    }
    func mainDrawingChanged() {
        guard !closed, !nativeStrokeActive, !installing, model.page?.id == pageID else { return }
        syncFromMain()
    }
    private func syncFromMain() {
        if copiedGeneration != model.inkDisplayGeneration {
            let target = model.canvas.drawing
            if !NativeInkComparison.equal(target, host.canvas.drawing) { replaceChild(target) }
            copiedGeneration = model.inkDisplayGeneration
        }
        host.surface.page = model.page ?? host.surface.page
        host.alignSurface()
    }
    private func replaceChild(_ drawing: PKDrawing) {
        installing = true; defer { installing = false }
        let canvas = host.canvas, enabled = host.canvas.drawingGestureRecognizer.isEnabled
        canvas.delegate = nil; canvas.drawingGestureRecognizer.isEnabled = false
        canvas.drawing = PKDrawing(); canvas.drawing = PKDrawing(strokes: drawing.strokes)
        canvas.undoManager?.removeAllActions(); canvas.delegate = self
        canvas.drawingGestureRecognizer.isEnabled = enabled
        host.emptyInkCover.resetForPageChange(); host.markerReadability.reset(); host.updateNativeInkVisibility()
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        guard available, model.tool == .pen, canvasView === host.canvas else { return }
        // Do not replace the child container while PencilKit is beginning this native touch.
        completeNativeStroke()
        nativeStrokeActive = true; model.strokeBegan()
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !installing, canvasView === host.canvas, nativeStrokeActive else { return }
        host.updateNativeInkVisibility(); host.markerReadability.update(host, forceInk: true)
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard nativeStrokeActive, canvasView === host.canvas else { return }
        ending?.cancel()
        ending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            self?.completeNativeStroke()
        }
    }
    /// Also used on background/dismiss: commit exactly the delivered native value,
    /// retaining masks, pressure, azimuth, timestamps and page coordinates.
    func completeNativeStroke() {
        ending?.cancel(); ending = nil
        guard nativeStrokeActive else { return }
        let drawing = host.canvas.drawing
        let changed = model.inkGestureBaseline.map { !NativeInkComparison.equal($0, drawing) } ?? false
        nativeStrokeActive = false; installing = true
        if !changed {
            model.cancelGuidedInk(model.canvas.drawing); installing = false; syncFromMain(); return
        }
        if model.page?.id == pageID {
            model.installNativeInk(drawing); model.strokeEnded(); model.finishInkGesture()
            if model.editBeforeGesture != nil { model.cancelGuidedInk(model.canvas.drawing) }
        }
        installing = false; syncFromMain()
        if let stroke = drawing.strokes.last, stroke.path.count > 0 {
            let end = stroke.path[stroke.path.count - 1].location.applying(stroke.transform)
            advance(after: end)
        }
    }
    private func customFinished() {
        mainDrawingChanged()
        if model.tool == .marker, let end = host.drawingAssistant?.lastCompletedPoint { advance(after: end) }
    }
    func finishAndClose() {
        guard !closed else { return }
        completeNativeStroke(); host.drawingAssistant?.cancel(); closed = true
        host.canvas.delegate = nil; host.canvas.drawingGestureRecognizer.isEnabled = false
        overview?.removeFromSuperview(); overview = nil
        if model.zoomWritingController === self { model.zoomWritingController = nil }
        model.rulerActive = originalRuler; model.protractorActive = originalProtractor
        model.zoomWritingOpen = false
        let parent = model.canvas
        parent.panGestureRecognizer.isEnabled = true; parent.pinchGestureRecognizer?.isEnabled = true
    }
    func step(_ direction: Int) { guard !model.hasActiveStroke else { return }; geometry?.step(direction); updateViewport() }
    func newLine() { guard !model.hasActiveStroke else { return }; geometry?.newLine(spacing: lineSpacing); updateViewport() }
    func move(to point: CGPoint) { guard !model.hasActiveStroke else { return }; geometry?.move(to: .init(x: point.x, y: point.y)); updateViewport() }
    func setZoom(_ value: Double) {
        guard !model.hasActiveStroke else { return }
        geometry?.resize(panelWidth: host.bounds.width, panelHeight: host.bounds.height, zoom: value); updateViewport()
    }
    func margins(left: Double, right: Double) { guard !model.hasActiveStroke else { return }; geometry?.margins(left: left, right: right); updateViewport() }
    private var lineSpacing: Double? { model.page?.paper == .ruled ? model.page?.appearance?.spacing ?? 32 : nil }
    private func advance(after point: CGPoint) {
        guard automatic else { return }
        geometry?.advance(after: .init(x: point.x, y: point.y), lineSpacing: lineSpacing); updateViewport()
    }
    private func updateViewport() { host.writingViewport = geometry; host.setNeedsLayout(); host.layoutIfNeeded(); overview?.refresh() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { if !installing { host.alignSurface() } }
}
