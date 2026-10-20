import UIKit
import NeuralNotesCore

/// Only the visible paper is rasterized at screen resolution. This avoids a
/// full-page bitmap at 8x zoom and keeps PDF/text sharp within a bounded viewport.
@MainActor
final class VisiblePaperDetail: UIView {
    private var page: PageSnapshot?
    private var package = URL(fileURLWithPath: "/")
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private var hiddenTextID: UUID?
    func update(from host: CanvasHost) {
        let z = host.canvas.zoomScale, rect = host.surface.frame.intersection(host.bounds)
        isHidden = z <= 1 || rect.isNull || rect.isEmpty
        guard !isHidden else { return }
        let at = CGPoint(x: (rect.minX - host.surface.frame.minX) / z, y: (rect.minY - host.surface.frame.minY) / z)
        let changed = frame != rect || page != host.surface.page || package != host.surface.package || zoom != z || origin != at || hiddenTextID != host.surface.hiddenTextID
        frame = rect; isUserInteractionEnabled = false
        let budget = sqrt(8_000_000 / max(1, rect.width * rect.height))
        contentScaleFactor = min(host.window?.screen.scale ?? UIScreen.main.scale, budget)
        page = host.surface.page; package = host.surface.package; zoom = z; origin = at; hiddenTextID = host.surface.hiddenTextID
        if changed { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
        guard let page, let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        PageRenderer.draw(page, package: package, in: context, hidingTextID: hiddenTextID)
    }
}
