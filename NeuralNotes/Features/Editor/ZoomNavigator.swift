import UIKit
import NeuralNotesCore

/// Read-only overview of the same canvas. Writing stays in the existing
/// PKCanvasView; no nested scroll view or second drawing surface is installed.
@MainActor
final class ZoomNavigator: UIView {
    private let thumbnail = UIImageView(), viewport = CAShapeLayer(), close = UIButton(type: .system)
    private weak var host: CanvasHost?
    private var generation = ""
    private var imageTask: Task<Void, Never>?
    func resetForPageChange() {
        imageTask?.cancel(); imageTask = nil
        generation = ""; thumbnail.image = nil; viewport.path = nil
    }
    init() {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground; layer.cornerRadius = 14; layer.shadowOpacity = 0.2; layer.shadowRadius = 8
        thumbnail.contentMode = .scaleToFill; thumbnail.clipsToBounds = true
        viewport.fillColor = UIColor.systemTeal.withAlphaComponent(0.15).cgColor; viewport.strokeColor = UIColor.systemTeal.cgColor; viewport.lineWidth = 2
        addSubview(thumbnail); thumbnail.layer.addSublayer(viewport)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); close.addTarget(self, action: #selector(hide), for: .touchUpInside)
        close.accessibilityLabel = "Chiudi navigatore zoom"; addSubview(close)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(navigate(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(navigate(_:)))
        for gesture in [pan as UIGestureRecognizer, tap] {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            addGestureRecognizer(gesture)
        }
        isHidden = true; accessibilityIdentifier = "zoomNavigator"
        NotificationCenter.default.addObserver(self, selector: #selector(nnPDFNavigatorPreviewReady(_:)), name: PDFRasterCache.didRender, object: nil)
        thumbnail.isAccessibilityElement = true; thumbnail.accessibilityLabel = "Panoramica del foglio"; thumbnail.accessibilityHint = "Tocca o trascina con un dito per spostare l’area ingrandita."
    }
    required init?(coder: NSCoder) { nil }
    deinit { imageTask?.cancel(); NotificationCenter.default.removeObserver(self) }
    @objc private func nnPDFNavigatorPreviewReady(_ note: Notification) {
        guard let host, let page = host.model?.page, PDFRasterCache.affects(note, page: page, package: host.surface.package, previewOnly: true) else { return }
        generation = ""; update(host)
    }
    @objc private func hide() { host?.model?.showZoomNavigator = false }
    @objc private func navigate(_ gesture: UIGestureRecognizer) {
        guard let host, let page = host.model?.page else { return }
        let point = gesture.location(in: thumbnail)
        guard thumbnail.bounds.contains(point) else { return }
        host.centerWritingArea(CGPoint(x: point.x / thumbnail.bounds.width * page.width, y: point.y / thumbnail.bounds.height * page.height))
    }
    func update(_ host: CanvasHost) {
        self.host = host
        guard let model = host.model, model.showZoomNavigator, let page = model.page else { isHidden = true; return }
        isHidden = false
        let width: CGFloat = 146, height = min(210, width * page.height / page.width)
        frame = CGRect(x: max(4, host.bounds.width - width - 24), y: max(12, host.bounds.height - height - 64), width: width + 16, height: height + 40)
        close.frame = CGRect(x: bounds.width - 42, y: 0, width: 44, height: 36)
        thumbnail.frame = CGRect(x: 8, y: 32, width: width, height: height)
        let key = "\(page.id)|\(page.revision)|\(model.activeLayerID?.uuidString ?? "base")|\(model.inkDisplayGeneration)"
        if generation != key && !model.hasActiveStroke {
            generation = key
            imageTask?.cancel()
            let drawing = host.canvas.drawing, owner = model.activeLayerID, workspace = model.workspace
            imageTask = Task { [weak self] in
                do {
                    let image = try await DocumentServices.compositeImage(page: page, drawing: drawing, drawingLayerID: owner,
                        workspace: workspace, maxDimension: 400, pdfMode: .preview)
                    guard !Task.isCancelled, let self, self.generation == key else { return }
                    self.thumbnail.image = image
                } catch { /* Derived preview: the live page stays authoritative. */ }
            }
        }
        let visible = host.surface.convert(host.bounds, from: host).intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        if visible.isNull { viewport.path = nil }
        else {
            let scaleX = width / page.width, scaleY = height / page.height
            viewport.path = UIBezierPath(rect: CGRect(x: visible.minX * scaleX, y: visible.minY * scaleY, width: visible.width * scaleX, height: visible.height * scaleY)).cgPath
        }
        host.bringSubviewToFront(self)
    }
}
