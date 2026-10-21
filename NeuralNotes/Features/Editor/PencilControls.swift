import SwiftUI
import UIKit

@MainActor
final class PencilControls: NSObject, UIPencilInteractionDelegate {
    private weak var host: CanvasHost?
    private weak var model: EditorViewModel?
    private var current = InkTool.pen, previous = InkTool.marker, lastInk = InkTool.pen
    private let hover = UIHoverGestureRecognizer()
    private let cursor = CAShapeLayer()
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init()
        let pencil = UIPencilInteraction(); pencil.delegate = self; host.addInteraction(pencil)
        hover.addTarget(self, action: #selector(hovered(_:))); hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        host.addGestureRecognizer(hover); cursor.fillColor = UIColor.clear.cgColor; cursor.lineWidth = 1
        host.layer.addSublayer(cursor)
    }
    func trackTool() {
        guard let model else { return }
        if model.tool != current { previous = current; current = model.tool }
        if model.tool == .pen || model.tool == .marker { lastInk = model.tool }
    }
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { perform(UIPencilInteraction.preferredTapAction) }
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { perform(UIPencilInteraction.preferredTapAction) }
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        perform(UIPencilInteraction.preferredSqueezeAction, point: squeeze.hoverPose?.location)
    }
    private func perform(_ action: UIPencilPreferredAction, point: CGPoint? = nil) {
        guard let model, !model.hasActiveStroke, model.editingTextID == nil, !model.navigating else { return }
        switch action {
        case .ignore: break
        case .switchEraser: model.chooseTool((model.tool == .eraser ? lastInk : .eraser).workspaceTool)
        case .switchPrevious: model.chooseTool(previous.workspaceTool)
        case .showColorPalette: showOptions(at: point)
        default: showOptions(at: point)
        }
    }
    private func showOptions(at point: CGPoint?) {
        guard let host, let model, host.window != nil else { return }
        var responder: UIResponder? = host
        while let next = responder, !(next is UIViewController) { responder = next.next }
        guard let presenter = responder as? UIViewController, presenter.presentedViewController == nil else { return }
        let controller = UIHostingController(rootView: ScrollView { ToolOptionsPopover(model: model, tool: model.tool.workspaceTool) })
        controller.modalPresentationStyle = .popover
        controller.preferredContentSize = CGSize(width: 330, height: max(180, min(600, host.bounds.height - 40)))
        let at = point ?? CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        controller.popoverPresentationController?.sourceView = host
        controller.popoverPresentationController?.sourceRect = CGRect(x: max(0, min(host.bounds.maxX - 2, at.x)), y: max(0, min(host.bounds.maxY - 2, at.y)), width: 2, height: 2)
        presenter.present(controller, animated: true)
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        guard #available(iOS 17.5, *), let host, let model, UIPencilInteraction.prefersHoverToolPreview, !model.hasActiveStroke,
              gesture.state == .began || gesture.state == .changed else { cursor.path = nil; return }
        let at = gesture.location(in: host)
        let width = model.tool == .eraser ? model.writingOptions.eraserWidth : model.tool == .marker ? max(12, model.thickness * 5) : model.thickness
        let diameter = max(4, width * Double(host.canvas.zoomScale))
        cursor.strokeColor = model.tool == .eraser ? UIColor.systemGray.cgColor : PaperInk.color(model.ink).cgColor
        cursor.path = UIBezierPath(ovalIn: CGRect(x: at.x - diameter / 2, y: at.y - diameter / 2, width: diameter, height: diameter)).cgPath
    }
}
