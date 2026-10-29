import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A second finger disables snapping without moving the primary drag point.
@MainActor
final class SnapPanGestureRecognizer: UIPanGestureRecognizer {
    private weak var primary: UITouch?
    private(set) var suspendsSnapping = false
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, primary != nil || touches.count > 1 { state = .failed; return }
        if primary == nil { primary = touches.first(where: { $0.type == .pencil }) ?? touches.first }
        if let primary { suspendsSnapping = SnapTouchModifiers.active(primary: primary, event: event) }
        super.touchesBegan(touches, with: event)
    }
    override func location(in view: UIView?) -> CGPoint { primary?.location(in: view) ?? super.location(in: view) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let primary { suspendsSnapping = SnapTouchModifiers.active(primary: primary, event: event) }
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let ended = primary.map { touches.contains($0) } ?? false
        if let primary { suspendsSnapping = SnapTouchModifiers.active(primary: primary, event: event, includingEnded: ended) }
        super.touchesEnded(touches, with: event)
        if ended, state == .began || state == .changed { state = .ended }
    }
    override func reset() { primary = nil; suspendsSnapping = false; super.reset() }
}

@MainActor
enum SnapTouchModifiers {
    /// Inspect the complete event, including fingers outside the handle view.
    /// On primary lift, simultaneous lifts still count as a held modifier. This
    /// snapshot is taken before UIKit dispatches the gesture's final action.
    static func active(primary: UITouch, event: UIEvent, includingEnded: Bool = false) -> Bool {
        (event.allTouches ?? []).contains { touch in
            guard touch !== primary, touch.type == .direct || touch.type == .pencil else { return false }
            let simultaneousLift = includingEnded && touch.phase == .ended && abs(touch.timestamp - primary.timestamp) <= 0.02
            return touch.phase == .began || touch.phase == .moved || touch.phase == .stationary || simultaneousLift
        }
    }
}
