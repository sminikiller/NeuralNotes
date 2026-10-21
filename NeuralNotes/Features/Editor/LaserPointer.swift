import UIKit

@MainActor
final class LaserPointerOverlay: UIView {
    private let trail = CAShapeLayer(), dot = CAShapeLayer()
    private var points: [CGPoint] = []
    private var tracked: UITouch?
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false; isHidden = true; isMultipleTouchEnabled = false
        trail.strokeColor = UIColor.systemRed.cgColor; trail.fillColor = nil; trail.lineWidth = 4; trail.lineCap = .round; trail.lineJoin = .round
        dot.fillColor = UIColor.systemRed.cgColor; dot.shadowColor = UIColor.systemRed.cgColor; dot.shadowRadius = 8; dot.shadowOpacity = 0.8
        layer.addSublayer(trail); layer.addSublayer(dot)
        isAccessibilityElement = true; accessibilityLabel = "Puntatore laser temporaneo"; accessibilityIdentifier = "laserPointer"
    }
    required init?(coder: NSCoder) { nil }
    func update(_ host: CanvasHost) {
        frame = host.bounds
        let active = host.model?.laserActive == true
        if isHidden == active { clear() }; isHidden = !active
        if active { host.bringSubviewToFront(self) }
    }
    private func clear() {
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        tracked = nil; points = []; trail.removeAllAnimations(); dot.removeAllAnimations()
        trail.path = nil; dot.path = nil; trail.opacity = 1; dot.opacity = 1
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked == nil, let touch = touches.first else { return }
        clear(); tracked = touch; add(touch.location(in: self))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] { add(sample.location(in: self)) }
    }
    private func add(_ point: CGPoint) {
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        points.append(point); if points.count > 80 { points.removeFirst(points.count - 80) }
        let path = UIBezierPath(); if let first = points.first { path.move(to: first) }
        for point in points.dropFirst() { path.addLine(to: point) }; trail.path = path.cgPath
        dot.path = UIBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)).cgPath
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
    private func finish() {
        tracked = nil
        if UIAccessibility.isReduceMotionEnabled { clear(); return }
        for item in [trail, dot] {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.65
            item.opacity = 0; item.add(fade, forKey: "fade")
        }
    }
}

@MainActor
extension EditorViewModel {
    func setLaserActive(_ active: Bool) {
        guard !interactionBusy, !navigating, !loading else { return }
        laserActive = active; configureTool(); (pagePresenter as? CanvasHost)?.alignSurface()
    }
}
