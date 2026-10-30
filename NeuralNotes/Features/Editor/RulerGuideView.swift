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
    private var resizing: UIPinchGestureRecognizer!
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Righello: due dita per spostare e ruotare, pizzica per cambiare lunghezza"; accessibilityIdentifier = "rulerGuide"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(nnHandleRulerPan(_:))); pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(nnHandleRulerRotation(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(nnHandleRulerResize(_:)))
        moving = pan; turning = rotation; resizing = pinch
        for gesture in [pan as UIGestureRecognizer, rotation, pinch] {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]; gesture.delegate = self
            gesture.isEnabled = false; host.addGestureRecognizer(gesture)
        }
        host.canvas.panGestureRecognizer.require(toFail: pan)
        host.canvas.pinchGestureRecognizer?.require(toFail: rotation)
        host.canvas.pinchGestureRecognizer?.require(toFail: pinch)
        host.addSubview(self)
    }
    required init?(coder: NSCoder) { return nil }
    func update() {
        guard let host, let model, let page = model.page else { isHidden = true; moving.isEnabled = false; turning.isEnabled = false; resizing.isEnabled = false; return }
        isHidden = !model.rulerActive || model.loading || (model.tool != .pen && model.tool != .marker)
        moving.isEnabled = !isHidden; turning.isEnabled = !isHidden; resizing.isEnabled = !isHidden
        guard !isHidden else { return }
        if pageID != page.id { pageID = page.id; model.rulerGuide = RulerGuide(x: page.width / 2, y: page.height / 2) }
        var guide = model.rulerGuide
        if !model.hasActiveStroke {
            let thickness = max(80, 58 / max(0.1, host.canvas.zoomScale))
            if abs(guide.thickness - thickness) > 0.1 { guide.thickness = thickness; model.rulerGuide = guide }
        }
        transform = .identity; bounds = CGRect(x: 0, y: 0, width: max(240, min(1800, guide.length)), height: guide.thickness)
        center = host.surface.convert(CGPoint(x: guide.x, y: guide.y), to: host)
        transform = CGAffineTransform(rotationAngle: guide.angle).scaledBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        accessibilityValue = model.guideReadout ?? String(format: "%.0f gradi", guide.angle * 180 / .pi)
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
        let title = (model?.guideReadout ?? String(format: "↔ %.0f° · 2 dita: sposta/ruota · pizzica: lunghezza", (model?.rulerGuide.angle ?? 0) * 180 / .pi)) as NSString
        let zoom = max(0.1, host?.canvas.zoomScale ?? 1)
        let style: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 11 / zoom, weight: .medium), .foregroundColor: UIColor.label]
        let size = title.size(withAttributes: style)
        title.draw(at: CGPoint(x: max(6, bounds.midX - size.width / 2), y: bounds.midY - size.height / 2), withAttributes: style)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { model?.hasActiveStroke == false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isHidden && touch.type == .direct && bounds.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { other === moving || other === turning || other === resizing }
    // UIView inherits UIResponder.move(_:). Gesture actions need distinct
    // Objective-C selectors even when their Swift parameter types differ.
    @objc private func nnHandleRulerPan(_ pan: UIPanGestureRecognizer) {
        guard let host, let model, let page = model.page, !model.hasActiveStroke else { return }
        if pan.state == .began { original.x = model.rulerGuide.x; original.y = model.rulerGuide.y }
        let translation = pan.translation(in: host.surface)
        var guide = model.rulerGuide
        guide.x = min(page.width, max(0, original.x + translation.x)); guide.y = min(page.height, max(0, original.y + translation.y))
        model.rulerGuide = guide; model.guideReadout = nil; update()
    }
    @objc private func nnHandleRulerRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.angle = model.rulerGuide.angle }
        var guide = model.rulerGuide; guide.angle = original.angle + gesture.rotation
        if gesture.state == .ended { guide.snapAngle() }
        model.rulerGuide = guide; model.guideReadout = nil; update()
    }
    @objc private func nnHandleRulerResize(_ gesture: UIPinchGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.length = model.rulerGuide.length }
        var guide = model.rulerGuide; guide.length = max(240, min(1800, original.length * Double(gesture.scale)))
        model.rulerGuide = guide; model.guideReadout = nil; update()
    }

}
