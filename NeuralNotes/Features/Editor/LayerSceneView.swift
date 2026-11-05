import UIKit
import PencilKit
import NeuralNotesCore

/// Visible composition sits above the native canvas, passes every touch
/// through, and never changes its opacity/history. Only the active owner's
/// live ink is prepared each frame; inactive owners remain bounded maps.
@MainActor
final class LayerSceneView: UIView {
    private weak var host: CanvasHost?
    private var page: PageSnapshot?
    private var ownerID: UUID?
    private var signature: PageSnapshot?
    private var lastRawPage: PageSnapshot?
    private var fallback: LayerScene?
    private var detail: LayerScene?
    private var fallbackTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var epoch = UUID()
    private var failedFallbackEpoch: UUID?
    private var recognitionBaseline: PKDrawing?
    private var recognitionToken = UUID()
    private var detailTicket = UUID()
    private var detailRequest: (CGRect, CGFloat, PageSnapshot, Set<UUID>, UUID?)?
    private var detailSuspended = false
    private var detailBlockedByInk = false
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private var visiblePage = CGRect.zero
    private var hiding = Set<UUID>()
    private var hidingTextID: UUID?
    private var inkGeneration = UUID()
    private let inkCache = ActiveLayerInkCache()
    private var ownerProgram: PreparedLayerOwner?
    private var ownerProgramPage: PageSnapshot?
    private var ownerProgramToken: UUID?
    private var ownerProgramLocalToken: UUID?
    private var ownerProgramBounds = CGRect.zero
    private var ownerProgramScale: CGFloat = 0
    private var ownerProgramHidden = Set<UUID>()
    private var ownerProgramTextID: UUID?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private(set) var isReady = false
    var cachedBytes: Int { (fallback?.byteCost ?? 0) + (detail?.byteCost ?? 0) }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false; isOpaque = true; backgroundColor = .white; isHidden = true
        isAccessibilityElement = true; accessibilityIdentifier = "layerSceneStatus"
        accessibilityLabel = "Livelli della pagina"
        spinner.hidesWhenStopped = true; addSubview(spinner)
        NotificationCenter.default.addObserver(self, selector: #selector(nnLayerPDFReady(_:)), name: PDFRasterCache.didRender, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(nnLayerMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    deinit { fallbackTask?.cancel(); detailTask?.cancel(); NotificationCenter.default.removeObserver(self) }
    @objc private func nnLayerPDFReady(_ note: Notification) {
        if let page, let host, PDFRasterCache.affects(note, page: page, package: host.surface.package) { setNeedsDisplay() }
    }
    @objc private func nnLayerMemoryWarning() {
        detailTask?.cancel(); detailTask = nil; detail = nil; detailRequest = nil
        detailSuspended = true; inkCache.clear(); ownerProgram = nil; setNeedsDisplay()
    }
    func reset() {
        fallbackTask?.cancel(); detailTask?.cancel(); fallbackTask = nil; detailTask = nil
        epoch = UUID(); failedFallbackEpoch = nil; recognitionBaseline = nil; detailTicket = UUID(); detailRequest = nil
        fallback = nil; detail = nil; page = nil; ownerID = nil; signature = nil; lastRawPage = nil
        inkCache.clear(); ownerProgram = nil; ownerProgramPage = nil; ownerProgramToken = nil
        isReady = false; isHidden = true; layer.contents = nil; spinner.stopAnimating()
    }
    @discardableResult
    func prepareForInput(_ host: CanvasHost) async -> Bool {
        update(host)
        // The complete fallback is the input barrier. Detail is deliberately
        // independent and can be cancelled as soon as the user starts writing.
        await fallbackTask?.value
        return isReady
    }
    func showRecognitionBaseline(_ drawing: PKDrawing?) {
        recognitionBaseline = drawing; recognitionToken = UUID(); setNeedsDisplay()
    }
    func pauseDetailForInk() {
        detailBlockedByInk = true
        detailTask?.cancel(); detailTask = nil; detailRequest = nil; detailTicket = UUID()
    }
    func inkDidChange() { inkGeneration = UUID(); if let host { update(host) } }

    func update(_ host: CanvasHost) {
        guard let model = host.model, let next = model.page, next.layers != nil else {
            if !isHidden || page != nil { reset() }; return
        }
        self.host = host
        if model.hasActiveStroke { if !detailBlockedByInk { pauseDetailForInk() } }
        else { detailBlockedByInk = false }
        let owner = model.activeLayerID ?? next.id
        let visible = host.surface.frame.intersection(host.bounds)
        guard !visible.isNull, !visible.isEmpty else { isHidden = true; return }
        let nextZoom = max(0.05, host.canvas.zoomScale)
        let at = CGPoint(x: (visible.minX - host.surface.frame.minX) / nextZoom, y: (visible.minY - host.surface.frame.minY) / nextZoom)
        let viewport = CGRect(origin: at, size: CGSize(width: visible.width / nextZoom, height: visible.height / nextZoom))
        if viewport != visiblePage || nextZoom != zoom { detailSuspended = false }
        let identityChanged = page?.id != next.id || ownerID != owner
        if identityChanged { reset(); self.host = host }
        if lastRawPage != next || identityChanged {
            let normalized = LayerScene.fingerprint(next, owner: owner)
            if normalized != signature {
                epoch = UUID(); fallbackTask?.cancel(); fallbackTask = nil
                detailTask?.cancel(); detailTask = nil; detailRequest = nil; detailTicket = UUID()
                signature = normalized
            }
            lastRawPage = next
        }
        page = next; ownerID = owner; frame = visible; zoom = nextZoom; origin = at; visiblePage = viewport
        var hiddenIDs = host.surface.allHiddenObjectIDs
        if let id = host.surface.hiddenObjectID { hiddenIDs.insert(id) }
        if hiddenIDs != hiding || host.surface.hiddenTextID != hidingTextID {
            hiding = hiddenIDs; hidingTextID = host.surface.hiddenTextID
            epoch = UUID(); fallbackTask?.cancel(); fallbackTask = nil
            detailTask?.cancel(); detailTask = nil; detailRequest = nil; detailTicket = UUID()
        }
        let screenScale = host.window?.screen.scale ?? UIScreen.main.scale
        contentScaleFactor = min(screenScale, sqrt(6_000_000 / max(1, visible.width * visible.height)))
        spinner.center = CGPoint(x: bounds.midX, y: min(30, bounds.midY))
        isHidden = false
        if let signature {
            if !matches(fallback, signature: signature) && fallbackTask == nil && failedFallbackEpoch != epoch {
                prepareFallback(next, owner: owner, model: model, signature: signature)
            }
            let wantedScale = max(0.01, contentScaleFactor * zoom)
            let covered = matches(detail, signature: signature) && detail?.bounds.contains(viewport) == true &&
                (detail?.requestedScale ?? 0) >= wantedScale / 1.25
            if !covered && !detailSuspended && !detailBlockedByInk && matches(fallback, signature: signature) {
                let expanded = viewport.insetBy(dx: -viewport.width * 0.15, dy: -viewport.height * 0.15)
                    .intersection(CGRect(x: 0, y: 0, width: next.width, height: next.height))
                prepareDetail(next, owner: owner, model: model, signature: signature, region: expanded, scale: wantedScale)
            }
        }
        refreshReady(); setNeedsDisplay()
    }

    private func matches(_ scene: LayerScene?, signature: PageSnapshot) -> Bool {
        scene?.fingerprint == signature && scene?.ownerID == ownerID && scene?.hiding == hiding && scene?.hidingTextID == hidingTextID
    }
    private func prepareFallback(_ page: PageSnapshot, owner: UUID, model: EditorViewModel, signature: PageSnapshot) {
        let ticket = epoch, previous = fallback, hiddenIDs = hiding, text = hidingTextID, workspace = model.workspace
        let region = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        fallbackTask = Task { [weak self, weak model] in
            do {
                let result = try await LayerScene.prepare(page: page, owner: owner, workspace: workspace, bounds: region,
                    requestedScale: min(1, 400 / max(region.width, region.height)), budget: LayerScene.fallbackBudget,
                    previous: previous, hiding: hiddenIDs, hidingTextID: text)
                guard !Task.isCancelled, let self, self.epoch == ticket, self.signature == signature else { return }
                self.fallback = result; self.fallbackTask = nil; self.refreshReady(); self.setNeedsDisplay()
                if let host = self.host { self.update(host) }
            } catch {
                guard !Task.isCancelled, let self, self.epoch == ticket else { return }
                self.fallbackTask = nil; self.failedFallbackEpoch = ticket; self.detailSuspended = true
                model?.error = "Impossibile preparare i livelli: \(error.localizedDescription)"
            }
        }
    }
    private func prepareDetail(_ page: PageSnapshot, owner: UUID, model: EditorViewModel, signature: PageSnapshot, region: CGRect, scale: CGFloat) {
        guard !region.isNull, !region.isEmpty else { return }
        if let request = detailRequest, request.0 == region, request.1 == scale, request.2 == signature,
           request.3 == hiding, request.4 == hidingTextID { return }
        detailTask?.cancel(); detailTicket = UUID()
        let ticket = detailTicket, generation = epoch, previous = detail
        let hiddenIDs = hiding, text = hidingTextID, workspace = model.workspace
        detailRequest = (region, scale, signature, hiddenIDs, text)
        detailTask = Task { [weak self] in
            do {
                let result = try await LayerScene.prepare(page: page, owner: owner, workspace: workspace, bounds: region,
                    requestedScale: scale, budget: LayerScene.detailBudget, previous: previous, hiding: hiddenIDs, hidingTextID: text)
                guard !Task.isCancelled, let self, self.detailTicket == ticket, self.epoch == generation else { return }
                self.detail = result; self.detailTask = nil; self.refreshReady(); self.setNeedsDisplay()
            } catch {
                guard !Task.isCancelled, let self, self.detailTicket == ticket else { return }
                self.detailTask = nil; self.detailSuspended = true
                // The complete fallback remains usable after a detail failure.
            }
        }
    }
    private func refreshReady() {
        if let signature { isReady = matches(fallback, signature: signature) || (matches(detail, signature: signature) && detail?.bounds.contains(visiblePage) == true) }
        else { isReady = false }
        accessibilityValue = isReady ? "Pronto" : "Preparazione"
        if isReady { spinner.stopAnimating() } else { spinner.startAnimating() }
        host?.handwritingPreview.update()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        drawScene(in: context, bounds: visiblePage)
    }
    func drawScene(in context: CGContext, bounds: CGRect, drawing override: PKDrawing? = nil,
                   marker: CGPath? = nil, color: UIColor? = nil, sourceToken: UUID? = nil) {
        guard let host, let model = host.model, let page, let ownerID else { return }
        PageRenderer.drawPaper(page, package: host.surface.package, in: context, pdfMode: .interactive)
        guard let signature else { return }
        let scene: LayerScene?
        if matches(detail, signature: signature), detail?.bounds.contains(bounds) == true { scene = detail }
        else if matches(fallback, signature: signature) { scene = fallback }
        else { scene = nil }
        guard let scene else { return }
        scene.below?.draw(in: context, bounds: scene.bounds)
        let active = scene.activeGroup.layer
        if active.isVisible, (active.opacity ?? 1) > 0 {
            let generation = sourceToken ?? (recognitionBaseline == nil ? model.inkDisplayGeneration : recognitionToken)
            let scale = max(0.01, contentScaleFactor * zoom)
            if active.composition != nil {
                let group = scene.activeGroup
                if ownerProgram == nil || ownerProgramToken != generation || ownerProgramLocalToken != inkGeneration ||
                    ownerProgramPage != signature || ownerProgramBounds != bounds || ownerProgramScale != scale || hidingTextID != ownerProgramTextID || hiding != ownerProgramHidden {
                    let appending = override != nil || recognitionBaseline != nil || ((model.tool == .pen || model.tool == .marker) && model.inkGestureBaseline != nil)
                    let token = sourceToken ?? (recognitionBaseline != nil ? recognitionToken : model.inkGestureGeneration)
                    ownerProgram = PreparedLayerOwner(group: group, page: page, package: host.surface.package,
                        drawing: override ?? recognitionBaseline ?? host.canvas.drawing, bounds: bounds, scale: scale,
                        hiding: hiding, hidingTextID: hidingTextID, rootToken: appending ? token : nil, previous: ownerProgram)
                    ownerProgramPage = signature; ownerProgramToken = generation; ownerProgramLocalToken = inkGeneration
                    ownerProgramBounds = bounds; ownerProgramScale = scale
                    ownerProgramHidden = hiding; ownerProgramTextID = hidingTextID
                }
                LayerBlendCompositor.drawGroup(opacity: active.opacity ?? 1, bounds: bounds, in: context) {
                    ownerProgram?.draw(in: $0, marker: marker, color: color)
                }
            } else {
            let canAppend = override == nil && recognitionBaseline == nil && (model.tool == .pen || model.tool == .marker)
            let baseline = canAppend ? model.inkGestureBaseline : nil
            inkCache.prepare(drawing: override ?? recognitionBaseline ?? host.canvas.drawing,
                baseline: baseline, baselineToken: baseline == nil ? nil : model.inkGestureGeneration,
                token: generation, localToken: inkGeneration, bounds: bounds, scale: scale)
            LayerBlendCompositor.drawGroup(opacity: active.opacity ?? 1, bounds: bounds, in: context) { target in
                scene.under?.draw(in: target, bounds: scene.bounds)
                inkCache.drawMarkers(in: target)
                if let marker, let color {
                    target.saveGState(); target.setBlendMode(.multiply); target.setAlpha(0.25)
                    target.setFillColor(color.withAlphaComponent(1).cgColor); target.addPath(marker); target.fillPath(); target.restoreGState()
                }
                inkCache.drawPens(in: target)
                scene.over?.draw(in: target, bounds: scene.bounds)
            }
            }
        }
        scene.above?.draw(in: context, bounds: scene.bounds)
    }
}
