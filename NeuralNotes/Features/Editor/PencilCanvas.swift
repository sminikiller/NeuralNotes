import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
final class CanvasHost: UIView {
    let surface = PageSurfaceView()
    let canvas: PKCanvasView
    private var lastSize = CGSize.zero
    private(set) var fitsPageWidth = false
    var interaction: CanvasInteraction?
    var textInput: CanvasTextInput?
    var drawingAssistant: CanvasDrawingAssistant?
    weak var model: EditorViewModel?
    var flow: ContinuousCanvasFlow?
    private let inputShield = PendingPageInputShield()
    private var hintTask: Task<Void, Never>?
    let pullHint = UILabel()

    init(canvas: PKCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        backgroundColor = UIColor.secondarySystemBackground
        clipsToBounds = true
        surface.overrideUserInterfaceStyle = .light
        PaperInk.configure(canvas)
        PaperInk.configureNavigation(canvas, fingerDrawing: false)
        addSubview(surface); addSubview(canvas)
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        pullHint.text = "Rilascia per avanzare · nuova pagina se sei all’ultima"
        pullHint.font = .preferredFont(forTextStyle: .caption1); pullHint.textAlignment = .center
        pullHint.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        pullHint.layer.cornerRadius = 12; pullHint.clipsToBounds = true; pullHint.isHidden = true
        pullHint.isUserInteractionEnabled = false; addSubview(pullHint)
        inputShield.isUserInteractionEnabled = true; inputShield.isOpaque = false; addSubview(inputShield)
    }
    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        inputShield.frame = bounds
        pullHint.frame = CGRect(x: 12, y: max(0, bounds.height - 58), width: max(0, bounds.width - 24), height: 36)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = CGSize(width: surface.page.width, height: surface.page.height)
        let reference = flow?.fitReference ?? size
        let fit = min((bounds.width - 24) / reference.width, (bounds.height - 24) / reference.height)
        let resized = lastSize != bounds.size
        if resized {
            canvas.zoomScale = 1
            canvas.contentSize = size
            canvas.minimumZoomScale = max(0.1, fit)
            canvas.maximumZoomScale = max(4, max(fit * 4, bounds.width / size.width))
            canvas.zoomScale = canvas.minimumZoomScale
            lastSize = bounds.size
        }
        // UIScrollView creates its pinch recognizer when zoom is enabled.
        // Configure it after setting the range, as well as on tool changes.
        PaperInk.configureNavigation(canvas, fingerDrawing: model?.fingerDrawing ?? false)
        if model?.tool == .shape { canvas.panGestureRecognizer.minimumNumberOfTouches = 2 }
        alignSurface()
        if resized { fitPage(animated: false) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let model, let flow, flow.enabled, let touch = event?.allTouches?.first(where: { touch in
            let at = touch.location(in: self)
            return touch.phase == .began && hypot(at.x - point.x, at.y - point.y) < 2
        }), touch.type == .pencil || (model.fingerDrawing && touch.type == .direct) {
            if !flow.prepareInput(at: point) { return inputShield }
        }
        return super.hitTest(point, with: event)
    }

    func synchronizePage() {
        guard let model, let page = model.page else { return }
        let changed = surface.page.id != page.id || surface.page.width != page.width || surface.page.height != page.height
        if surface.page != page { surface.page = page }
        let changedMode = flow?.updateSource() ?? false
        if changed || changedMode {
            if flow?.restorePendingViewport(for: page.id) != true { resetPage() }
        }
        interaction?.refresh(); textInput?.refresh(); alignSurface()
    }

    func resetPage() {
        fitsPageWidth = false
        lastSize = .zero
        canvas.setContentOffset(CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top), animated: false)
        setNeedsLayout()
    }

    func showPageInputHint(_ text: String) {
        hintTask?.cancel(); pullHint.text = text; pullHint.isHidden = false; bringSubviewToFront(pullHint)
        hintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.pullHint.isHidden = true
        }
    }

    func fitPage(animated: Bool) {
        let changes = {
            self.fitsPageWidth = false
            self.canvas.setZoomScale(self.canvas.minimumZoomScale, animated: false)
            self.alignSurface()
            let offset = self.flow?.preferredOffset() ?? CGPoint(x: -self.canvas.contentInset.left, y: -self.canvas.contentInset.top)
            self.canvas.setContentOffset(offset, animated: false)
            self.alignSurface()
        }
        if animated { UIView.animate(withDuration: 0.25, animations: changes) }
        else { changes() }
    }

    /// Double tap alternates whole-page and edge-to-edge width. The explicit
    /// Pagina intera command still always restores the whole page.
    func togglePageZoom(animated: Bool) {
        layoutIfNeeded()
        guard bounds.width > 0, bounds.height > 0, surface.page.width > 0 else { return }
        if fitsPageWidth || canvas.zoomScale > canvas.minimumZoomScale * 1.01 {
            fitPage(animated: animated); return
        }
        let centerY = surface.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self).y
        let zoom = bounds.width / CGFloat(surface.page.width)
        let changes = {
            self.fitsPageWidth = true
            self.canvas.maximumZoomScale = max(self.canvas.maximumZoomScale, zoom)
            self.canvas.setZoomScale(zoom, animated: false)
            self.alignSurface()
            let height = CGFloat(self.surface.page.height) * zoom
            let y = height > self.bounds.height
                ? max(0, min(height - self.bounds.height, centerY * zoom - self.bounds.height / 2))
                : -(self.bounds.height - height) / 2
            self.canvas.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            self.alignSurface()
        }
        if animated { UIView.animate(withDuration: 0.25, animations: changes) }
        else { changes() }
    }

    func alignSurface() {
        if flow?.arrange() == true {
            interaction?.refresh(); textInput?.layout(); return
        }
        let zoom = canvas.zoomScale
        let size = CGSize(width: surface.page.width, height: surface.page.height)
        let extent = CGSize(width: size.width * zoom, height: size.height * zoom)
        if canvas.contentSize != extent { canvas.contentSize = extent }
        surface.bounds = CGRect(origin: .zero, size: size)
        surface.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        let sideMargin: CGFloat = fitsPageWidth ? 0 : 12
        let inset = UIEdgeInsets(top: max(12, (bounds.height - size.height * zoom) / 2),
            left: max(sideMargin, (bounds.width - size.width * zoom) / 2), bottom: 12, right: sideMargin)
        if canvas.contentInset != inset { canvas.contentInset = inset }
        surface.center = CGPoint(x: size.width * zoom / 2 - canvas.contentOffset.x,
                                 y: size.height * zoom / 2 - canvas.contentOffset.y)
        interaction?.refresh()
        textInput?.layout()
    }
}

@MainActor
struct PencilCanvas: UIViewRepresentable {
    let model: EditorViewModel

    func makeUIView(context: Context) -> CanvasHost {
        let host = CanvasHost(canvas: model.canvas)
        host.surface.package = model.workspace.package
        host.surface.page = model.page ?? PageSnapshot()
        host.model = model
        host.flow = ContinuousCanvasFlow(host: host, model: model)
        model.pagePresenter = host
        model.canvas.delegate = context.coordinator
        context.coordinator.host = host
        host.interaction = CanvasInteraction(host: host, model: model)
        host.textInput = CanvasTextInput(host: host, model: model)
        host.drawingAssistant = CanvasDrawingAssistant(host: host, model: model)
        model.drawingAssistant = host.drawingAssistant
        PaperInk.configureNavigation(model.canvas, fingerDrawing: model.fingerDrawing)
        return host
    }

    func updateUIView(_ host: CanvasHost, context: Context) {
        host.synchronizePage()
        if context.coordinator.lastFitRequest != model.fitPageRequest {
            context.coordinator.lastFitRequest = model.fitPageRequest
            host.layoutIfNeeded(); host.fitPage(animated: true)
        }
        host.alignSurface()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let model: EditorViewModel
        weak var host: CanvasHost?
        var lastFitRequest = 0
        init(model: EditorViewModel) { self.model = model }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { model.drawingChanged() }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { model.strokeBegan() }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { model.strokeEnded() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.alignSurface()
            // Read the final geometry after layout: several zoom callbacks may
            // arrive before SwiftUI can update, especially during rotation.
            Task { @MainActor [weak self] in
                guard let self else { return }
                let canvas = self.model.canvas
                let zoomed = self.host?.fitsPageWidth == true || canvas.zoomScale > canvas.minimumZoomScale * 1.05
                if self.model.canvasZoomed != zoomed { self.model.canvasZoomed = zoomed }
            }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.alignSurface()
            let ready = scrollView.isDragging && readyForNext(scrollView)
            if ready { host?.pullHint.text = "Rilascia per avanzare · nuova pagina se sei all’ultima" }
            host?.pullHint.isHidden = !ready
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { host?.flow?.dragBegan() }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { host?.flow?.scrollSettled() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            let advance = readyForNext(scrollView); host?.pullHint.isHidden = true
            if advance { Task { await model.advanceOrAddPage() } }
            else if !decelerate { host?.flow?.scrollSettled() }
        }
        private func readyForNext(_ scroll: UIScrollView) -> Bool {
            let enabled = model.currentWorkspace.pullNext
            guard enabled, model.pageNavigation == .single, model.hasLease, !model.interactionBusy, !model.navigating, !model.loading,
                  model.canvas.zoomScale <= model.canvas.minimumZoomScale * 1.05, let page = model.page else { return false }
            let height = CGFloat(page.height) * model.canvas.zoomScale
            let end = max(-scroll.contentInset.top, height - scroll.bounds.height + scroll.contentInset.bottom)
            return scroll.contentOffset.y - end > 110
        }
    }
}
