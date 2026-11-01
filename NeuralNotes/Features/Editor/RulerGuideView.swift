import UIKit
import NeuralNotesCore

@MainActor
final class RulerGuideView: UIView, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private var pageID: UUID?
    private var original = RulerGuide()
    private let moving = UIPanGestureRecognizer(), turning = UIRotationGestureRecognizer(), resizing = UIPinchGestureRecognizer()
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        isAccessibilityElement = true; accessibilityIdentifier = "rulerGuide"; accessibilityTraits = .adjustable
        accessibilityLabel = "Guida da disegno: trascina per spostare, due dita per ruotare, pizzica per ridimensionare"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Sposta a sinistra") { [weak self] _ in self?.adjust(dx: -20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta a destra") { [weak self] _ in self?.adjust(dx: 20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in alto") { [weak self] _ in self?.adjust(dy: -20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in basso") { [weak self] _ in self?.adjust(dy: 20) ?? false },
            UIAccessibilityCustomAction(name: "Ruota di 15 gradi") { [weak self] _ in self?.adjust(angle: .pi / 12) ?? false }
        ]
        moving.addTarget(self, action: #selector(nnHandleRulerPan(_:)))
        turning.addTarget(self, action: #selector(nnHandleRulerRotation(_:)))
        resizing.addTarget(self, action: #selector(nnHandleRulerResize(_:)))
        for gesture in [moving as UIGestureRecognizer, turning, resizing] {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            gesture.delegate = self; gesture.isEnabled = false; host.addGestureRecognizer(gesture)
        }
        host.canvas.panGestureRecognizer.require(toFail: moving)
        host.canvas.pinchGestureRecognizer?.require(toFail: turning)
        host.canvas.pinchGestureRecognizer?.require(toFail: resizing)
        host.addSubview(self)
    }
    required init?(coder: NSCoder) { nil }
    func update() {
        guard let host, let model, let page = model.page else { setEnabled(false); return }
        setEnabled(model.rulerActive && !model.loading && (model.tool == .pen || model.tool == .marker))
        moving.minimumNumberOfTouches = model.fingerDrawing ? 2 : 1; moving.maximumNumberOfTouches = 2
        guard !isHidden else { return }
        if pageID != page.id {
            pageID = page.id
            let kind = model.rulerGuide.kind
            model.rulerGuide = RulerGuide(x: page.width / 2, y: page.height / 2); model.rulerGuide.kind = kind
        }
        let thickness = max(80, 72 / max(0.1, Double(host.canvas.zoomScale)))
        if !model.hasActiveStroke, abs(model.rulerGuide.thickness - thickness) > 0.1 { model.rulerGuide.thickness = thickness }
        frame = host.bounds
        let vertices = model.rulerGuide.vertices.map { host.surface.convert(CGPoint(x: $0.x, y: $0.y), to: self) }
        let box = vertices.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1))) }.intersection(bounds)
        accessibilityFrame = UIAccessibility.convertToScreenCoordinates(box, in: self)
        accessibilityValue = model.guideReadout ?? String(format: "%.0f gradi, lunghezza %.0f punti", model.rulerGuide.angle * 180 / .pi, model.rulerGuide.length)
        host.bringSubviewToFront(self); setNeedsDisplay()
    }
    private func setEnabled(_ enabled: Bool) {
        isHidden = !enabled
        for gesture in [moving as UIGestureRecognizer, turning, resizing] where gesture.isEnabled != enabled { gesture.isEnabled = enabled }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let host, let model else { return }
        let guide = model.rulerGuide, zoom = max(0.05, host.canvas.zoomScale)
        let corners = guide.vertices.map { host.surface.convert(CGPoint(x: $0.x, y: $0.y), to: self) }
        let path = UIBezierPath(); for (i, at) in corners.enumerated() { if i == 0 { path.move(to: at) } else { path.addLine(to: at) } }; path.close()
        context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.14).cgColor); context.addPath(path.cgPath); context.fillPath()
        context.setStrokeColor(UIColor.systemTeal.cgColor); context.setLineWidth(1.2); context.addPath(path.cgPath); context.strokePath()
        let edges = guide.kind == .ruler ? [0, 2] : Array(corners.indices)
        for i in edges {
            let a = corners[i], b = corners[(i + 1) % corners.count], span = hypot(b.x - a.x, b.y - a.y)
            guard span > 0 else { continue }
            let ux = (b.x - a.x) / span, uy = (b.y - a.y) / span
            let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let center = host.surface.convert(CGPoint(x: guide.x, y: guide.y), to: self)
            let sign: CGFloat = (center.x - middle.x) * -uy + (center.y - middle.y) * ux >= 0 ? 1 : -1
            for tick in stride(from: CGFloat(0), through: span, by: max(4, 10 * zoom)) {
                let number = Int((tick / max(4, 10 * zoom)).rounded()), size: CGFloat = number % 5 == 0 ? 13 : 6
                let at = CGPoint(x: a.x + tick * ux, y: a.y + tick * uy)
                context.move(to: at); context.addLine(to: CGPoint(x: at.x - uy * size * sign, y: at.y + ux * size * sign))
            }
        }; context.strokePath()
        let title = model.guideReadout ?? "Penna sul bordo · trascina, ruota o pizzica con le dita"
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.label]
        let text = title as NSString, size = text.size(withAttributes: attributes)
        let bottom = corners.map(\.y).max() ?? bounds.midY
        let centerX = corners.map(\.x).reduce(0, +) / CGFloat(corners.count)
        let width = min(bounds.width - 16, size.width + 16)
        let box = CGRect(x: min(max(8, centerX - width / 2), bounds.width - width - 8), y: min(max(8, bottom + 10), bounds.height - size.height - 24), width: width, height: size.height + 10)
        context.setFillColor(UIColor.secondarySystemBackground.withAlphaComponent(0.95).cgColor)
        context.addPath(UIBezierPath(roundedRect: box, cornerRadius: 8).cgPath); context.fillPath()
        text.draw(in: box.insetBy(dx: 8, dy: 5), withAttributes: attributes)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { model?.hasActiveStroke == false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !isHidden, touch.type == .direct, let host, let model else { return false }
        let at = touch.location(in: host.surface)
        let vertices = model.rulerGuide.vertices
        if gestureRecognizer === turning || gestureRecognizer === resizing {
            // Two finger rotation/pinch often straddles a triangle's diagonal.
            // Reserve its bounding area for those gestures, not for single-finger panning.
            let box = vertices.reduce(CGRect.null) { $0.union(CGRect(x: $1.x, y: $1.y, width: 1, height: 1)) }
            return box.contains(at)
        }
        return ShapeGeometry.contains(.init(x: at.x, y: at.y), polygon: vertices)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { other === moving || other === turning || other === resizing }
    override func accessibilityIncrement() { _ = adjust(scale: 1.1) }
    override func accessibilityDecrement() { _ = adjust(scale: 1 / 1.1) }
    private func adjust(dx: Double = 0, dy: Double = 0, angle: Double = 0, scale: Double = 1) -> Bool {
        guard !isHidden, let model, let page = model.page, !model.hasActiveStroke else { return false }
        model.rulerGuide.x = min(page.width, max(0, model.rulerGuide.x + dx))
        model.rulerGuide.y = min(page.height, max(0, model.rulerGuide.y + dy))
        model.rulerGuide.angle += angle; model.rulerGuide.length = min(1800, max(160, model.rulerGuide.length * scale))
        model.guideReadout = nil; update(); return true
    }
    @objc private func nnHandleRulerPan(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let page = model.page, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.x = model.rulerGuide.x; original.y = model.rulerGuide.y }
        let delta = gesture.translation(in: host.surface)
        model.rulerGuide.x = min(page.width, max(0, original.x + Double(delta.x)))
        model.rulerGuide.y = min(page.height, max(0, original.y + Double(delta.y))); model.guideReadout = nil; update()
    }
    @objc private func nnHandleRulerRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.angle = model.rulerGuide.angle }
        model.rulerGuide.angle = original.angle + Double(gesture.rotation)
        if gesture.state == .ended { model.rulerGuide.snapAngle() }
        model.guideReadout = nil; update()
    }
    @objc private func nnHandleRulerResize(_ gesture: UIPinchGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.length = model.rulerGuide.length }
        model.rulerGuide.length = min(1800, max(160, original.length * Double(gesture.scale))); model.guideReadout = nil; update()
    }
}
