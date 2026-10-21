import UIKit
import NeuralNotesCore

@MainActor
final class RulerGuideView: UIView, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private var pageID: UUID?
    private var original = RulerGuide()
    private var moving: UIPanGestureRecognizer!
    private var turning: UIRotationGestureRecognizer!
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        accessibilityLabel = "Righello: sposta e ruota con due dita"; accessibilityIdentifier = "rulerGuide"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(move(_:))); pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        moving = pan; turning = rotation
        for gesture in [pan as UIGestureRecognizer, rotation] {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]; gesture.delegate = self
            gesture.isEnabled = false; host.addGestureRecognizer(gesture)
        }
        host.canvas.panGestureRecognizer.require(toFail: pan)
        host.canvas.pinchGestureRecognizer?.require(toFail: rotation)
        host.addSubview(self)
    }
    required init?(coder: NSCoder) { return nil }
    func update() {
        guard let host, let model, let page = model.page else { isHidden = true; moving.isEnabled = false; turning.isEnabled = false; return }
        isHidden = !model.rulerActive || model.loading || (model.tool != .pen && model.tool != .marker)
        moving.isEnabled = !isHidden; turning.isEnabled = !isHidden
        guard !isHidden else { return }
        if pageID != page.id { pageID = page.id; model.rulerGuide = RulerGuide(x: page.width / 2, y: page.height / 2) }
        let guide = model.rulerGuide
        transform = .identity; bounds = CGRect(x: 0, y: 0, width: min(900, page.width * 0.9), height: RulerGuide.halfWidth * 2)
        center = host.surface.convert(CGPoint(x: guide.x, y: guide.y), to: host)
        transform = CGAffineTransform(rotationAngle: guide.angle).scaledBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        host.bringSubviewToFront(self); setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.18).cgColor); context.fill(bounds)
        context.setStrokeColor(UIColor.systemTeal.cgColor); context.setLineWidth(1)
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
        for i in stride(from: 0, to: Int(bounds.width), by: 10) {
            let length: CGFloat = i % 50 == 0 ? 12 : 6
            context.move(to: CGPoint(x: CGFloat(i), y: 0)); context.addLine(to: CGPoint(x: CGFloat(i), y: length))
            context.move(to: CGPoint(x: CGFloat(i), y: bounds.height)); context.addLine(to: CGPoint(x: CGFloat(i), y: bounds.height - length))
        }; context.strokePath()
        let title = String(format: "↔  %.0f°  ·  due dita", (model?.rulerGuide.angle ?? 0) * 180 / .pi)
        (title as NSString).draw(at: CGPoint(x: max(12, bounds.midX - 62), y: 14), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.label])
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { model?.hasActiveStroke == false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isHidden && touch.type == .direct && bounds.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { other === moving || other === turning }
    @objc private func move(_ pan: UIPanGestureRecognizer) {
        guard let host, let model, let page = model.page, !model.hasActiveStroke else { return }
        if pan.state == .began { original = model.rulerGuide }
        let translation = pan.translation(in: host.surface)
        var guide = model.rulerGuide
        guide.x = min(page.width, max(0, original.x + translation.x)); guide.y = min(page.height, max(0, original.y + translation.y))
        model.rulerGuide = guide; update()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.angle = model.rulerGuide.angle }
        var guide = model.rulerGuide; guide.angle = original.angle + gesture.rotation
        if gesture.state == .ended { guide.snapAngle() }
        model.rulerGuide = guide; update()
    }
}
