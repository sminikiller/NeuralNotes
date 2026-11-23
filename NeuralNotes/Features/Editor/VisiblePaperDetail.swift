import UIKit
import NeuralNotesCore

/// Only the visible paper is rasterized at screen resolution. This avoids a
/// full-page bitmap at 8x zoom and keeps PDF/text sharp within a bounded viewport.
@MainActor
final class VisiblePaperDetail: UIView {
    private let retained = RetainedPaperRaster()
    init() {
        super.init(frame: .zero)
        clipsToBounds = true; isUserInteractionEnabled = false; isOpaque = false
        retained.paint = { [weak self] context in self?.paint(in: context) }
        addSubview(retained)
        NotificationCenter.default.addObserver(self, selector: #selector(nnPDFDetailReady(_:)), name: PDFRasterCache.didRender, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func nnPDFDetailReady(_ note: Notification) {
        if let page, !isHidden, PDFRasterCache.affects(note, page: page, package: package) { setNeedsDisplay() }
    }
    private(set) var redrawRequests = 0
    private var region = CGRect.zero
    private var page: PageSnapshot?
    private var package = URL(fileURLWithPath: "/")
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private var hiddenTextID: UUID?
    private var hiddenObjectID: UUID?
    private var hiddenObjectIDs = Set<UUID>()
    override func setNeedsDisplay() {
        super.setNeedsDisplay(); retained.setNeedsDisplay()
    }
    /// Explicit display fence for snapshot tests; UIKit normally displays the
    /// retained child with the rest of the view hierarchy at the frame boundary.
    func displayPaperIfNeeded() { layer.displayIfNeeded(); retained.layer.displayIfNeeded() }
    func resetForPageChange() {
        page = nil; region = .zero; hiddenTextID = nil; layer.contents = nil; retained.layer.contents = nil; isHidden = true
    }
    func update(from host: CanvasHost, force: Bool = false) {
        if host.surface.page.layers != nil { if !isHidden || page != nil { resetForPageChange() }; return }
        let z = host.canvas.zoomScale, rect = host.surface.frame.intersection(host.bounds)
        isHidden = (!force && z <= 1 && host.surface.page.pdfFile == nil) || rect.isNull || rect.isEmpty
        guard !isHidden else { return }
        let at = CGPoint(x: (rect.minX - host.surface.frame.minX) / z, y: (rect.minY - host.surface.frame.minY) / z)
        let visible = CGRect(origin: at, size: CGSize(width: rect.width / z, height: rect.height / z))
        let moving = host.canvas.isDragging || host.canvas.isDecelerating || host.canvas.isZooming || host.viewportAnimationActive
        let contentChanged = page?.hasSamePaperContent(as: host.surface.page) != true || package != host.surface.package || hiddenTextID != host.surface.hiddenTextID || hiddenObjectID != host.surface.hiddenObjectID || hiddenObjectIDs != host.surface.allHiddenObjectIDs
        let needsResolution = zoom != z && (!moving || z / zoom > 1.5 || z / zoom < 0.67)
        let rebuild = contentChanged || !region.contains(visible) || needsResolution
        if rebuild {
            // Overscan retains the same backing bitmap while panning. Only the
            // layer position moves, instead of compositing every PDF tile on each frame.
            region = visible.insetBy(dx: -128 / z, dy: -128 / z)
                .intersection(CGRect(x: 0, y: 0, width: host.surface.page.width, height: host.surface.page.height))
            zoom = z; origin = region.origin
            page = host.surface.page; package = host.surface.package
            hiddenTextID = host.surface.hiddenTextID; hiddenObjectID = host.surface.hiddenObjectID
            hiddenObjectIDs = host.surface.allHiddenObjectIDs
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // The public viewport stays strictly inside the host. Only its clipped
        // child has overscan, so cached pixels can never cover toolbar/adjacent pages.
        frame = rect
        retained.bounds = CGRect(origin: .zero, size: CGSize(width: region.width * zoom, height: region.height * zoom))
        retained.transform = CGAffineTransform(scaleX: z / zoom, y: z / zoom)
        retained.center = CGPoint(x: host.surface.frame.minX + region.midX * z - rect.minX,
                                  y: host.surface.frame.minY + region.midY * z - rect.minY)
        let budget = sqrt(8_000_000 / max(1, retained.bounds.width * retained.bounds.height))
        contentScaleFactor = min(host.window?.screen.scale ?? UIScreen.main.scale, budget)
        retained.contentScaleFactor = contentScaleFactor
        CATransaction.commit()
        if rebuild { redrawRequests += 1; setNeedsDisplay() }
    }

    private func paint(in context: CGContext) {
        guard let page else { return }
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        PageRenderer.draw(page, package: package, in: context, hidingTextID: hiddenTextID, hidingObjectID: hiddenObjectID, hidingObjectIDs: hiddenObjectIDs, pdfMode: .interactive)
    }
}

@MainActor
private final class RetainedPaperRaster: UIView {
    var paint: ((CGContext) -> Void)?
    override func draw(_ rect: CGRect) {
        if let context = UIGraphicsGetCurrentContext() { paint?(context) }
    }
}
