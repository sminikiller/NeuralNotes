import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A second finger disables snapping without moving the primary drag point.
@MainActor
final class SnapPanGestureRecognizer: UIPanGestureRecognizer {
    private weak var primary: UITouch?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, primary != nil || touches.count > 1 { state = .failed; return }
        if primary == nil { primary = touches.first(where: { $0.type == .pencil }) ?? touches.first }
        super.touchesBegan(touches, with: event)
    }
    override func location(in view: UIView?) -> CGPoint { primary?.location(in: view) ?? super.location(in: view) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let ended = primary.map { touches.contains($0) } ?? false
        super.touchesEnded(touches, with: event)
        if ended, state == .began || state == .changed { state = .ended }
    }
    override func reset() { primary = nil; super.reset() }
}

@MainActor
final class SnapTouchMonitor: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    private var active: Set<ObjectIdentifier> = []
    init(host: CanvasHost) {
        self.host = host; super.init(target: nil, action: nil)
        delegate = self; cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { active.insert(ObjectIdentifier(touch)) }
        // Count tracked touches even while another recognizer changes state.
        host?.snapSecondTouch = active.count > 1
        state = state == .possible ? .began : .changed
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { active.remove(ObjectIdentifier(touch)) }
        host?.snapSecondTouch = active.count > 1
        if active.isEmpty { state = .ended }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { host?.snapSecondTouch = false; state = .cancelled }
    override func reset() { active = []; host?.snapSecondTouch = false; super.reset() }
}
