import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
final class LiveMarkerPreview: UIView {
    private weak var host: CanvasHost?
    private let page: PageSnapshot, baseline: PKDrawing, color: UIColor, token = UUID()
    private let composition = MarkerCompositionCache()
    private var footprint = CGPath(rect: .zero, transform: nil)
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    init(host: CanvasHost, page: PageSnapshot, baseline: PKDrawing, color: UIColor) {
        self.host = host; self.page = page; self.baseline = baseline; self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        accessibilityIdentifier = "liveMarkerPreview"
        host.addSubview(self)
    }
    required init?(coder: NSCoder) { nil }
    func update(path: CGPath) {
        guard let host, host.model?.page?.id == page.id else { isHidden = true; return }
        let visible = host.surface.frame.intersection(host.bounds)
        guard !visible.isNull, !visible.isEmpty else { isHidden = true; return }
        frame = visible; zoom = max(0.05, host.canvas.zoomScale)
        origin = CGPoint(x: (visible.minX - host.surface.frame.minX) / zoom, y: (visible.minY - host.surface.frame.minY) / zoom)
        contentScaleFactor = min(host.window?.screen.scale ?? UIScreen.main.scale, sqrt(2_000_000 / max(1, visible.width * visible.height)))
        footprint = path; isHidden = path.isEmpty; setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let host, let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -origin.x, y: -origin.y)
        context.addPath(footprint); context.clip()
        let visible = CGRect(origin: origin, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        composition.drawLiveMarker(page: page, baseline: baseline, token: token, footprint: footprint,
            color: color, package: host.surface.package, bounds: visible, scale: contentScaleFactor * zoom, in: context)
    }
}
