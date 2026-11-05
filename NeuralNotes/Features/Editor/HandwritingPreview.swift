import UIKit
import PencilKit
import NeuralNotesCore

/// Viewport-only disposable preview. The native drawing remains authoritative
/// until Applica; scrolling and zoom do not cause a disk write or PDF decode.
@MainActor final class HandwritingPreview: UIView {
    private weak var host: CanvasHost?
    private let composition = MarkerCompositionCache()
    private let leftHandle = UIView()
    private let rightHandle = UIView()
    private var dragLeft = false
    private var dragStart = CGPoint.zero
    private var dragWidth = 0.0
    private var dragOrigin = 0.0
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private var ghostImage: UIImage?
    private var ghostBounds = CGRect.null
    private var ghostScale: CGFloat = 0
    private weak var ghostSession: HandwritingSession?
    init() {
        super.init(frame: .zero); isOpaque = false; backgroundColor = .clear; isHidden = true
        accessibilityIdentifier = "handwritingPreview"
        for (index, handle) in [leftHandle, rightHandle].enumerated() {
            handle.backgroundColor = .systemTeal; handle.layer.cornerRadius = 10
            handle.layer.borderColor = UIColor.white.cgColor; handle.layer.borderWidth = 2
            handle.isAccessibilityElement = true; handle.accessibilityLabel = index == 0 ? "Larghezza grafia: bordo sinistro" : "Larghezza grafia: bordo destro"
            handle.accessibilityIdentifier = index == 0 ? "handwritingLeftHandle" : "handwritingRightHandle"
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(nnHandwritingWidth(_:))))
            addSubview(handle)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(nnHandwritingPDFReady(_:)), name: PDFRasterCache.didRender, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func nnHandwritingPDFReady(_ note: Notification) {
        if let host, let page = host.model?.page, PDFRasterCache.affects(note, page: page, package: host.surface.package) { setNeedsDisplay() }
    }
    func attach(_ host: CanvasHost) { self.host = host }
    func update() {
        guard let host, let session = host.model?.handwriting, session.isCurrent else {
            isHidden = true; layer.contents = nil; composition.clear(); ghostImage = nil; ghostSession = nil; return
        }
        let visible = host.surface.frame.intersection(host.bounds)
        guard !visible.isNull, !visible.isEmpty, session.preview != nil,
              session.before.page.layers == nil || host.layeredScene.isReady else { isHidden = true; return }
        frame = visible; zoom = max(0.05, host.canvas.zoomScale)
        origin = CGPoint(x: (visible.minX - host.surface.frame.minX) / zoom, y: (visible.minY - host.surface.frame.minY) / zoom)
        contentScaleFactor = min(host.window?.screen.scale ?? 2, sqrt(2_000_000 / max(1, visible.width * visible.height)))
        isHidden = false
        let y = min(bounds.height - 22, max(22, (session.selectionBounds.midY - origin.y) * zoom))
        let x0 = (session.left - origin.x) * zoom, x1 = (session.left + session.width - origin.x) * zoom
        for (handle, x) in [(leftHandle, x0), (rightHandle, x1)] {
            handle.frame = CGRect(x: x - 10, y: y - 18, width: 20, height: 36)
            handle.isHidden = session.command != .reflow || x < 0 || x > bounds.width
        }
        setNeedsDisplay()
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden else { return nil }
        for handle in [leftHandle, rightHandle] where !handle.isHidden {
            if handle.frame.insetBy(dx: -14, dy: -10).contains(point) { return handle }
        }
        return nil
    }
    @objc private func nnHandwritingWidth(_ recognizer: UIPanGestureRecognizer) {
        guard let session = host?.model?.handwriting, session.command == .reflow else { return }
        if recognizer.state == .began {
            dragLeft = recognizer.view === leftHandle
            dragStart = recognizer.location(in: self); dragWidth = session.width; dragOrigin = session.left
        }
        if recognizer.state == .changed || recognizer.state == .ended {
            let dx = Double((recognizer.location(in: self).x - dragStart.x) / zoom)
            if dragLeft {
                let end = dragOrigin + dragWidth
                session.left = max(0, min(end - session.minimumWidth, dragOrigin + dx))
                session.width = end - session.left
            } else { session.width = max(session.minimumWidth, min(session.maximumWidth, dragWidth + dx)) }
            session.recompute(); update()
        }
    }
    override func draw(_ rect: CGRect) {
        guard let host, let session = host.model?.handwriting, session.isCurrent,
              let preview = session.preview, let context = UIGraphicsGetCurrentContext() else { return }
        let page = session.before.page
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        let viewport = CGRect(origin: origin, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        if page.layers != nil {
            host.layeredScene.drawScene(in: context, bounds: viewport, drawing: preview, sourceToken: session.previewToken)
        } else {
            composition.draw(page: page, baseline: preview, token: session.previewToken, delta: PKDrawing(),
                package: host.surface.package, bounds: viewport, scale: contentScaleFactor * zoom,
                hiddenIDs: [], hiddenTextID: nil, in: context, pdfMode: .interactive)
            PageRenderer.drawSelected(Set(page.objectIDs), foreground: true, page: page, package: host.surface.package, in: context)
        }
        let scale = contentScaleFactor * zoom
        if ghostSession !== session || ghostBounds != viewport || ghostScale != scale {
            ghostImage = PaperInk.image(session.ghost, from: viewport, scale: scale)
            ghostSession = session; ghostBounds = viewport; ghostScale = scale
        }
        context.saveGState(); context.setAlpha(0.16)
        ghostImage?.draw(in: viewport)
        context.restoreGState()
        if session.command == .reflow {
            context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1 / zoom); context.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom])
            let box = session.selectionBounds
            for x in [session.left, session.left + session.width] {
                context.move(to: CGPoint(x: x, y: box.minY - 8)); context.addLine(to: CGPoint(x: x, y: box.maxY + 8))
            }
            context.strokePath()
        }
    }
}
