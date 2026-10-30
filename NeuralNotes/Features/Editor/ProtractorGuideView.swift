import UIKit
import NeuralNotesCore

@MainActor
final class ProtractorGuideView: UIView, UIGestureRecognizerDelegate {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    private var pageID: UUID?
    private var original = ProtractorGuide()
    private let moving: UIPanGestureRecognizer, turning: UIRotationGestureRecognizer, resizing: UIPinchGestureRecognizer
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        moving = UIPanGestureRecognizer(); turning = UIRotationGestureRecognizer(); resizing = UIPinchGestureRecognizer()
        super.init(frame: .zero)
        isOpaque = false; isUserInteractionEnabled = false; backgroundColor = .clear
        isAccessibilityElement = true; accessibilityIdentifier = "protractorGuide"
        accessibilityLabel = "Goniometro: trascina per spostare, due dita per ruotare, pizzica per cambiare dimensione"
        accessibilityTraits = .adjustable
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Sposta a sinistra") { [weak self] _ in self?.adjust(dx: -20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta a destra") { [weak self] _ in self?.adjust(dx: 20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in alto") { [weak self] _ in self?.adjust(dy: -20) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in basso") { [weak self] _ in self?.adjust(dy: 20) ?? false },
            UIAccessibilityCustomAction(name: "Ruota in senso orario di 15 gradi") { [weak self] _ in self?.adjust(angle: .pi / 12) ?? false },
            UIAccessibilityCustomAction(name: "Ruota in senso antiorario di 15 gradi") { [weak self] _ in self?.adjust(angle: -.pi / 12) ?? false }
        ]
        moving.addTarget(self, action: #selector(nnProtractorPan(_:)))
        turning.addTarget(self, action: #selector(nnProtractorRotation(_:)))
        resizing.addTarget(self, action: #selector(nnProtractorResize(_:)))
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
        guard let host, let model, let page = model.page else {
            isHidden = true; moving.isEnabled = false; turning.isEnabled = false; resizing.isEnabled = false; return
        }
        isHidden = !model.protractorActive || model.loading || (model.tool != .pen && model.tool != .marker)
        moving.isEnabled = !isHidden; turning.isEnabled = !isHidden; resizing.isEnabled = !isHidden
        moving.minimumNumberOfTouches = model.fingerDrawing ? 2 : 1; moving.maximumNumberOfTouches = 2
        guard !isHidden else { return }
        if pageID != page.id {
            pageID = page.id
            model.protractorGuide = ProtractorGuide(x: page.width / 2, y: page.height / 2,
                radius: min(220, max(80, min(page.width, page.height) * 0.23)), kind: model.currentWorkspace.protractorKind ?? .semicircle)
            model.protractorRays = []; model.guideReadout = nil
        }
        frame = host.bounds
        let guide = model.protractorGuide
        let corner = host.surface.convert(CGPoint(x: guide.x - guide.radius, y: guide.y - guide.radius), to: self)
        let diameter = CGFloat(guide.radius * 2) * host.canvas.zoomScale
        let accessibleBox = CGRect(origin: corner, size: CGSize(width: diameter, height: diameter)).intersection(bounds)
        accessibilityFrame = UIAccessibility.convertToScreenCoordinates(accessibleBox, in: self)
        accessibilityValue = model.guideReadout ?? String(format: "%d gradi, rotazione %.0f gradi, raggio %.0f punti", guide.kind == .circle ? 360 : 180, guide.rotation * 180 / .pi, guide.radius)
        host.bringSubviewToFront(self); setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let host, let model, let context = UIGraphicsGetCurrentContext(), model.protractorGuide.isValid else { return }
        let guide = model.protractorGuide, zoom = max(0.05, host.canvas.zoomScale)
        let pageZoom = Double(zoom)
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY); context.scaleBy(x: zoom, y: zoom)
        let degrees = guide.kind == .circle ? 360 : 180
        let path = UIBezierPath()
        for i in 0...degrees {
            guard let point = guide.point(at: Double(i) * .pi / 180) else { continue }
            if i == 0 { path.move(to: CGPoint(x: point.x, y: point.y)) } else { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        }
        path.close(); context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.12).cgColor)
        context.addPath(path.cgPath); context.fillPath()
        context.setStrokeColor(UIColor.systemTeal.cgColor); context.setLineWidth(1 / zoom)
        context.addPath(path.cgPath); context.strokePath()
        let darkPaper = model.page?.pdfFile == nil && model.page?.appearance?.tone == .slate
        let ink = darkPaper ? UIColor.white : UIColor.black
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 10 / zoom, weight: .regular), .foregroundColor: ink]
        for i in 0...degrees where i != 360 {
            let angle = Double(i) * .pi / 180
            let length = i % 10 == 0 ? 14.0 : (i % 5 == 0 ? 9 : 5)
            guard let a = guide.point(at: angle), let b = guide.point(at: angle, distance: max(0, guide.radius - length / pageZoom)) else { continue }
            context.move(to: CGPoint(x: a.x, y: a.y)); context.addLine(to: CGPoint(x: b.x, y: b.y))
            if i % 10 == 0, let at = guide.point(at: angle, distance: max(0, guide.radius - 26 / pageZoom)) {
                let text = "\(i)" as NSString, size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2), withAttributes: attributes)
            }
        }
        context.strokePath()
        context.setStrokeColor(UIColor.systemOrange.cgColor); context.setLineWidth(1.5 / zoom)
        for angle in model.protractorRays {
            guard let end = guide.point(at: angle) else { continue }
            context.move(to: CGPoint(x: guide.x, y: guide.y)); context.addLine(to: CGPoint(x: end.x, y: end.y))
        }
        context.move(to: CGPoint(x: guide.x - 8 / zoom, y: guide.y)); context.addLine(to: CGPoint(x: guide.x + 8 / zoom, y: guide.y))
        context.move(to: CGPoint(x: guide.x, y: guide.y - 8 / zoom)); context.addLine(to: CGPoint(x: guide.x, y: guide.y + 8 / zoom)); context.strokePath()
        let title = (model.guideReadout ?? (model.protractorMeasure ? "Parti dal centro · traccia due raggi" : "Penna sul bordo: arco · dal centro: raggio")) as NSString
        let style: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12 / zoom, weight: .medium), .foregroundColor: UIColor.label]
        let size = title.size(withAttributes: style)
        let center = CGPoint(x: guide.x, y: guide.y)
        let box = CGRect(x: center.x - size.width / 2 - 6 / zoom, y: center.y + 20 / zoom, width: size.width + 12 / zoom, height: size.height + 8 / zoom)
        context.setFillColor(UIColor.secondarySystemBackground.withAlphaComponent(0.95).cgColor)
        context.addPath(UIBezierPath(roundedRect: box, cornerRadius: 8 / zoom).cgPath); context.fillPath()
        title.draw(at: box.origin.applying(CGAffineTransform(translationX: 6 / zoom, y: 4 / zoom)), withAttributes: style)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { model?.hasActiveStroke == false }
    override func accessibilityIncrement() { _ = adjust(scale: 1.1) }
    override func accessibilityDecrement() { _ = adjust(scale: 1 / 1.1) }
    @discardableResult private func adjust(dx: Double = 0, dy: Double = 0, angle: Double = 0, scale: Double = 1) -> Bool {
        guard !isHidden, let model, let page = model.page, !model.hasActiveStroke else { return false }
        model.protractorGuide.x = min(page.width, max(0, model.protractorGuide.x + dx))
        model.protractorGuide.y = min(page.height, max(0, model.protractorGuide.y + dy))
        model.protractorGuide.rotation += angle
        model.protractorGuide.radius = min(1200, max(60, model.protractorGuide.radius * scale))
        model.guideReadout = nil; model.protractorRays = []; update(); return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !isHidden, let host, let model else { return false }
        let point = touch.location(in: host.surface), guide = model.protractorGuide
        let dx = Double(point.x) - guide.x, dy = Double(point.y) - guide.y
        let tolerance = 12 / Double(max(0.05, host.canvas.zoomScale))
        let localY = -dx * sin(guide.rotation) + dy * cos(guide.rotation)
        return hypot(dx, dy) <= guide.radius + tolerance && (guide.kind == .circle || localY <= tolerance)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { other === moving || other === turning || other === resizing }
    @objc private func nnProtractorPan(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let page = model.page, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.x = model.protractorGuide.x; original.y = model.protractorGuide.y }
        let delta = gesture.translation(in: host.surface)
        model.protractorGuide.x = min(page.width, max(0, original.x + Double(delta.x)))
        model.protractorGuide.y = min(page.height, max(0, original.y + Double(delta.y))); update()
    }
    @objc private func nnProtractorRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.rotation = model.protractorGuide.rotation }
        model.protractorGuide.rotation = original.rotation + Double(gesture.rotation); update()
    }
    @objc private func nnProtractorResize(_ gesture: UIPinchGestureRecognizer) {
        guard let model, !model.hasActiveStroke else { return }
        if gesture.state == .began { original.radius = model.protractorGuide.radius }
        model.protractorGuide.radius = min(1200, max(60, original.radius * Double(gesture.scale))); update()
    }
}
