import UIKit
import NeuralNotesCore

@MainActor
final class ShapeHandlesOverlay: UIView, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private var buttons: [ShapeHandleButton] = []
    private var source: ShapeElement?
    private var draft: ShapeElement?
    private var dragged: ShapeHandle?
    private var snapEngine: SnapEngine?
    private var lastSnappedRotation: Double?
    var isInteracting: Bool { draft != nil }

    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false
        let press = UILongPressGestureRecognizer(target: self, action: #selector(editVertex(_:)))
        press.delegate = self; addGestureRecognizer(press)
    }
    required init?(coder: NSCoder) { nil }
    func update() {
        guard let host, let model else { return }
        frame = host.bounds
        guard !model.selectionPageDragMode, model.tool == .objects || model.tool == .lasso,
              model.selectedIDs.count == 1, !model.selectionIncludesInk,
              let id = model.selectedObjectID, !(model.page?.lockedObjects ?? []).contains(id),
              let shape = model.page?.shapes?.first(where: { $0.id == id }) else { reset(); isHidden = true; return }
        isHidden = false
        let value = draft ?? shape
        let positions = ShapeHandles.positions(value, zoom: host.canvas.zoomScale)
        if buttons.map(\.handle) != positions.map(\.0) {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = positions.map { makeButton($0.0) }
            buttons.forEach { addSubview($0) }
        }
        for (button, position) in zip(buttons, positions) {
            let point = host.surface.convert(CGPoint(x: position.1.x, y: position.1.y), to: self)
            button.frame = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        }
        setNeedsDisplay()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden else { return false }
        if buttons.contains(where: { $0.frame.insetBy(dx: -13, dy: -13).contains(point) }) { return true }
        guard let shape = selectedShape, shape.kind == .freePolygon, let host else { return false }
        let at = host.surface.convert(point, from: self)
        var contour = shape; contour.fill = nil
        return ShapeGeometry.hit(.init(x: at.x, y: at.y), shape: contour, zoom: host.canvas.zoomScale, tolerance: 10)
    }
    override func draw(_ rect: CGRect) {
        guard let draft, let host, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY)
        context.scaleBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        ElementRendering.drawShape(draft, context: context, page: model?.page); context.restoreGState()
    }
    private var selectedShape: ShapeElement? {
        guard let id = model?.selectedObjectID else { return nil }
        return model?.page?.shapes?.first { $0.id == id }
    }
    private func makeButton(_ handle: ShapeHandle) -> ShapeHandleButton {
        let button = ShapeHandleButton(handle: handle)
        button.backgroundColor = .systemTeal; button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 2; button.layer.cornerRadius = handle == .rotation ? 9 : 5
        button.accessibilityLabel = handle.title; button.accessibilityIdentifier = "shapeHandle-\(handle)"
        let pan = SnapPanGestureRecognizer(target: self, action: #selector(moveHandle(_:)))
        pan.maximumNumberOfTouches = 2; button.addGestureRecognizer(pan)
        button.accessibilityCustomActions = handle == .rotation ? [
            UIAccessibilityCustomAction(name: "Ruota 15° a destra") { [weak self] _ in self?.rotateByDegrees(15) ?? false },
            UIAccessibilityCustomAction(name: "Ruota 15° a sinistra") { [weak self] _ in self?.rotateByDegrees(-15) ?? false }
        ] : [
            UIAccessibilityCustomAction(name: "Sposta a destra") { [weak self] _ in self?.adjust(handle, dx: 4, dy: 0) ?? false },
            UIAccessibilityCustomAction(name: "Sposta a sinistra") { [weak self] _ in self?.adjust(handle, dx: -4, dy: 0) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in alto") { [weak self] _ in self?.adjust(handle, dx: 0, dy: -4) ?? false },
            UIAccessibilityCustomAction(name: "Sposta in basso") { [weak self] _ in self?.adjust(handle, dx: 0, dy: 4) ?? false }
        ]
        return button
    }
    func rotateByDegrees(_ degrees: Double) -> Bool {
        guard degrees.isFinite, abs(degrees) <= 360, let model, model.hasLease, !model.interactionBusy,
              !model.loading, !model.navigating, var shape = selectedShape,
              !(model.page?.lockedObjects ?? []).contains(shape.id) else { return false }
        shape.rotation = ((shape.rotation ?? 0) + degrees).truncatingRemainder(dividingBy: 360)
        commit(shape, model: model); return true
    }
    private func adjust(_ handle: ShapeHandle, dx: Double, dy: Double) -> Bool {
        guard let model, let host, let shape = selectedShape,
              let at = ShapeHandles.positions(shape, zoom: host.canvas.zoomScale).first(where: { $0.0 == handle })?.1 else { return false }
        let result = ShapeHandles.moved(shape, handle: handle, to: .init(x: at.x + dx, y: at.y + dy),
            keepProportions: model.snapPreferences.keepProportions ?? false,
            snapRotation: model.snapPreferences.objectsEnabled, snapProportions: model.snapPreferences.objectsEnabled)
        commit(result, model: model); return true
    }
    @objc private func moveHandle(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let button = gesture.view as? ShapeHandleButton else { return }
        if gesture.state == .began {
            guard let shape = selectedShape, !model.interactionBusy else { return }
            source = shape; draft = shape; dragged = button.handle
            snapEngine = model.snapEngine(excluding: [shape.id]); lastSnappedRotation = nil
            model.cancelMaintenance(); model.movingObjects = true
            host.canvas.panGestureRecognizer.isEnabled = false
            if let page = model.page { host.diagramPreview?.start(page: page, moving: [shape.id]) }
            host.surface.hiddenObjectID = shape.id; host.foregroundObjects.update(host); host.paperDetail.update(from: host)
        }
        guard let source, let dragged else { return }
        if gesture.state == .cancelled || gesture.state == .failed { reset(); update(); return }
        let at = gesture.location(in: host.surface)
        let suspended = (gesture as? SnapPanGestureRecognizer)?.suspendsSnapping == true || gesture.modifierFlags.contains(.alternate)
        var target = StrokeSample(x: at.x, y: at.y)
        var guides: [SnapGuide] = []
        if dragged != .rotation && dragged != .innerRadius && dragged != .arcCurvature, let engine = snapEngine {
            let snapped = engine.snapPoint(target, zoom: host.canvas.zoomScale, preferences: model.snapPreferences, suspended: suspended)
            target = snapped.point; guides = snapped.guides
        }
        let snapping = !suspended && model.snapPreferences.objectsEnabled
        let value = ShapeHandles.moved(source, handle: dragged, to: target,
            keepProportions: model.snapPreferences.keepProportions ?? false, snapRotation: snapping, snapProportions: snapping)
        if dragged == .rotation, let rotation = value.rotation {
            let raw = atan2(at.y - (source.y + source.height / 2), at.x - (source.x + source.width / 2)) * 180 / .pi + 90
            let onStep = abs(rotation / 15 - (rotation / 15).rounded()) < 0.00001
            // Passing exactly through the snapped angle is still the same
            // bucket; clearing it there would produce a second vibration.
            if snapping && onStep && abs(rotation - raw) <= 3.001 {
                if rotation != lastSnappedRotation { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                lastSnappedRotation = rotation
            } else { lastSnappedRotation = nil }
        }
        // A square/proportion lock can move the handle away from a candidate.
        // Never leave a guide claiming an alignment that was not applied.
        if let actual = ShapeHandles.positions(value, zoom: host.canvas.zoomScale).first(where: { $0.0 == dragged })?.1 {
            guides = guides.filter { guide in
                abs(guide.from.x - guide.to.x) < 0.01 ? abs(actual.x - guide.from.x) < 0.1 : abs(actual.y - guide.from.y) < 0.1
            }
        }
        if value.hasValidOptions { draft = value }
        host.diagramPreview?.update(objects: [source.id: ConnectorObject(shape: value)])
        host.snapGuides?.show(guides); update()
        if gesture.state == .ended {
            let result = draft; reset()
            if let result { commit(result, model: model) }
            host.synchronizePage(); update()
        }
    }
    private func commit(_ shape: ShapeElement, model: EditorViewModel) {
        guard shape.hasValidOptions else { return }
        model.mutatePage("Modifica \(shape.kind.title)") { page in
            if let index = page.shapes?.firstIndex(where: { $0.id == shape.id }) { page.shapes?[index] = shape }
        }
    }
    func reset() {
        if draft != nil {
            model?.movingObjects = false
            host?.diagramPreview?.reset()
            if let host { host.surface.hiddenObjectID = nil; host.foregroundObjects.update(host); host.paperDetail.update(from: host) }
        }
        draft = nil; source = nil; dragged = nil; setNeedsDisplay()
        snapEngine = nil; lastSnappedRotation = nil; host?.snapGuides?.show([])
        if let host { PaperInk.configureNavigation(host.canvas, fingerDrawing: model?.fingerDrawing ?? false) }
    }
    @objc private func editVertex(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let host, let model, let shape = selectedShape,
              shape.kind == .freePolygon, !model.interactionBusy else { return }
        let at = gesture.location(in: host.surface)
        let local = ShapeGeometry.rotate(.init(x: at.x, y: at.y), shape: shape, inverse: true)
        var vertices = shape.vertices ?? [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)]
        let tolerance = 14 / max(0.1, host.canvas.zoomScale)
        let points = vertices.map { StrokeSample(x: shape.x + $0.x * shape.width, y: shape.y + $0.y * shape.height) }
        if let index = points.indices.first(where: { hypot(points[$0].x - local.x, points[$0].y - local.y) <= tolerance }) {
            guard vertices.count > 3 else { return }; vertices.remove(at: index)
        } else {
            guard vertices.count < 64,
                  let index = points.indices.min(by: {
                      ShapeGeometry.segmentDistance(local, points[$0], points[($0 + 1) % points.count]) < ShapeGeometry.segmentDistance(local, points[$1], points[($1 + 1) % points.count])
                  }) else { return }
            let endpoint = ShapeEndpoint(x: min(1, max(0, (local.x - shape.x) / shape.width)), y: min(1, max(0, (local.y - shape.y) / shape.height)))
            vertices.insert(endpoint, at: index + 1)
        }
        var result = shape; result.vertices = vertices; commit(result, model: model); update()
    }
}

@MainActor
private final class ShapeHandleButton: UIButton {
    let handle: ShapeHandle
    init(handle: ShapeHandle) { self.handle = handle; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -13, dy: -13).contains(point) }
}
