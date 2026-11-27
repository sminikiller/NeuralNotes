import UIKit
import PencilKit
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
    private var inkDrag: InkHandleDrag?
    private var inkPreview: UIImage?
    private var inkBox: CGRect?
    private var rotationBelow = false
    var isInteracting: Bool { draft != nil || inkDrag != nil }

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
        if model.selectionIncludesInk, !model.selectionPageDragMode, model.canEditActiveLayer,
           model.tool == .objects || model.tool == .lasso {
            let box = inkDrag?.box ?? model.selectionBounds
            if !box.isNull, !box.isEmpty {
                isHidden = false; inkBox = box
                let transform = inkDrag?.transform ?? .identity
                if inkDrag == nil {
                    rotationBelow = host.surface.convert(CGPoint(x: box.midX, y: box.minY), to: self).y < 52
                }
                let points: [(ShapeHandle, CGPoint)] = [
                    (.start, CGPoint(x: box.minX, y: box.midY)),
                    (.end, CGPoint(x: box.maxX, y: box.midY)),
                    (.rotation, CGPoint(x: box.midX, y: rotationBelow ? box.maxY : box.minY))
                ]
                place(points.map { handle, location in
                    var at = location.applying(transform)
                    if handle == .rotation {
                        let angle = (inkDrag?.radians ?? 0), gap: CGFloat = (rotationBelow ? -32 : 32) / max(0.05, host.canvas.zoomScale)
                        at.x += sin(angle) * gap; at.y -= cos(angle) * gap
                    }
                    return (handle, at)
                }, ink: true)
                return
            }
        }
        if inkBox != nil { reset() }
        guard !model.selectionPageDragMode, model.tool == .objects || model.tool == .lasso,
              model.selectedIDs.count == 1, !model.selectionIncludesInk,
              let id = model.selectedObjectID, !(model.page?.lockedObjects ?? []).contains(id),
              let shape = model.page?.shapes?.first(where: { $0.id == id }) else { reset(); isHidden = true; return }
        isHidden = false
        let value = draft ?? shape
        let positions = ShapeHandles.positions(value, zoom: host.canvas.zoomScale)
        place(positions.map { ($0.0, CGPoint(x: $0.1.x, y: $0.1.y)) }, ink: false)
    }
    private func place(_ positions: [(ShapeHandle, CGPoint)], ink: Bool) {
        guard let host else { return }
        if buttons.map(\.handle) != positions.map(\.0) || buttons.first?.isInk != ink {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = positions.map { makeButton($0.0, ink: ink) }
            buttons.forEach { addSubview($0) }
        }
        for (button, position) in zip(buttons, positions) {
            let point = host.surface.convert(position.1, to: self)
            let size = ink && button.handle != .rotation ? CGSize(width: 14, height: 20) : CGSize(width: 18, height: 18)
            button.bounds = CGRect(origin: .zero, size: size)
            button.center = point
        }
        setNeedsDisplay()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden else { return false }
        if buttons.contains(where: { $0.frame.insetBy(dx: -13, dy: -13).contains(point) }) { return true }
        guard inkBox == nil, let shape = selectedShape, shape.kind == .freePolygon, let host else { return false }
        let at = host.surface.convert(point, from: self)
        var contour = shape; contour.fill = nil
        return ShapeGeometry.hit(.init(x: at.x, y: at.y), shape: contour, zoom: host.canvas.zoomScale, tolerance: 10)
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if inkBox != nil, !isHidden, isUserInteractionEnabled {
            return buttons.filter { $0.point(inside: $0.convert(point, from: self), with: event) }
                .min { hypot($0.center.x - point.x, $0.center.y - point.y) < hypot($1.center.x - point.x, $1.center.y - point.y) }
        }
        return super.hitTest(point, with: event)
    }
    override func draw(_ rect: CGRect) {
        if let box = inkBox, let host, let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY)
            let zoom = max(0.05, host.canvas.zoomScale)
            context.scaleBy(x: zoom, y: zoom)
            context.concatenate(inkDrag?.transform ?? .identity)
            inkPreview?.draw(in: box, blendMode: .normal, alpha: 0.75)
            context.setLineWidth(2 / (zoom * (inkDrag?.scale ?? 1)))
            context.setStrokeColor(UIColor.systemTeal.cgColor); context.stroke(box)
            context.restoreGState()
            return
        }
        guard let draft, let host, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.translateBy(x: host.surface.frame.minX, y: host.surface.frame.minY)
        context.scaleBy(x: host.canvas.zoomScale, y: host.canvas.zoomScale)
        ElementRendering.drawShape(draft, context: context, page: model?.page); context.restoreGState()
    }
    private var selectedShape: ShapeElement? {
        guard let id = model?.selectedObjectID else { return nil }
        return model?.page?.shapes?.first { $0.id == id }
    }
    private func makeButton(_ handle: ShapeHandle, ink: Bool) -> ShapeHandleButton {
        let button = ShapeHandleButton(handle: handle, isInk: ink)
        button.backgroundColor = .systemTeal; button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 2; button.layer.cornerRadius = handle == .rotation ? 9 : 5
        button.accessibilityLabel = handle.title; button.accessibilityIdentifier = "shapeHandle-\(handle)"
        if ink {
            button.accessibilityLabel = handle == .rotation ? "Ruota selezione" : (handle == .start ? "Ridimensiona dal lato sinistro" : "Ridimensiona dal lato destro")
            button.accessibilityIdentifier = "inkHandle-\(handle)"
        }
        let pan = SnapPanGestureRecognizer(target: self, action: ink ? #selector(moveInkHandle(_:)) : #selector(moveHandle(_:)))
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
        if ink && handle != .rotation {
            button.accessibilityCustomActions = [("Ingrandisci", CGFloat(1.1)), ("Riduci", 1 / CGFloat(1.1))].map { name, factor in
                UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    guard let self, let box = self.inkBox, let model = self.model, !model.interactionBusy else { return false }
                    model.transformSelection(scale: factor, anchor: InkHandleDrag.anchor(for: handle, box: box))
                    self.update(); return true
                }
            }
        }
        return button
    }
    func rotateByDegrees(_ degrees: Double) -> Bool {
        if inkBox != nil, let model, model.selectionIncludesInk, model.canEditActiveLayer, !model.interactionBusy {
            model.transformSelection(degrees: degrees); update(); return true
        }
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
    @objc private func moveInkHandle(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let button = gesture.view as? ShapeHandleButton else { return }
        if gesture.state == .cancelled || gesture.state == .failed { reset(); update(); return }
        let point = gesture.location(in: host.surface)
        if gesture.state == .began {
            guard let box = inkBox, model.selectionIncludesInk, !model.interactionBusy else { return }
            let delta = gesture.translation(in: host.surface)
            inkDrag = InkHandleDrag(box: box, handle: button.handle,
                start: CGPoint(x: point.x - delta.x, y: point.y - delta.y))
            model.cancelMaintenance(); model.movingObjects = true
            host.canvas.panGestureRecognizer.isEnabled = false
            let indices = model.selectedStrokeIndices
            let strokes = model.canvas.drawing.strokes.enumerated().compactMap { indices?.contains($0.offset) == false ? nil : $0.element }
            let pixelScale = min(host.canvas.zoomScale * host.traitCollection.displayScale, sqrt(1_500_000 / max(1, box.width * box.height)))
            inkPreview = PKDrawing(strokes: strokes).image(from: box, scale: pixelScale)
        }
        guard var drag = inkDrag else { return }
        drag.move(to: point); inkDrag = drag; update()
        if gesture.state == .ended {
            reset()
            if drag.scale != 1 || drag.radians != 0 {
                model.transformSelection(scale: drag.scale, degrees: drag.radians * 180 / .pi, anchor: drag.pivot)
            }
            host.synchronizePage(); update()
        }
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
        if inkDrag != nil { model?.movingObjects = false }
        inkDrag = nil; inkPreview = nil; inkBox = nil
        if draft != nil {
            model?.movingObjects = false
            host?.diagramPreview?.reset()
            if let host { host.surface.hiddenObjectID = nil; host.foregroundObjects.update(host); host.paperDetail.update(from: host) }
        }
        draft = nil; source = nil; dragged = nil; setNeedsDisplay()
        snapEngine = nil; lastSnappedRotation = nil; host?.snapGuides?.show([])
        if let host { PaperInk.configureNavigation(host.canvas, fingerDrawing: model?.fingerDrawing ?? false) }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        inkBox == nil
    }
    @objc private func editVertex(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, inkBox == nil, let host, let model, let shape = selectedShape,
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
    let isInk: Bool
    init(handle: ShapeHandle, isInk: Bool) { self.isInk = isInk; self.handle = handle; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -13, dy: -13).contains(point) }
}


/// Page-space geometry shared by the live frame and the single undoable edit.
struct InkHandleDrag {
    let box: CGRect
    let handle: ShapeHandle
    let start: CGPoint
    var scale: CGFloat = 1
    var radians: CGFloat = 0
    static func anchor(for handle: ShapeHandle, box: CGRect) -> CGPoint {
        CGPoint(x: handle == .start ? box.maxX : (handle == .end ? box.minX : box.midX), y: box.midY)
    }
    var pivot: CGPoint { Self.anchor(for: handle, box: box) }
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: radians).scaledBy(x: scale, y: scale).translatedBy(x: -pivot.x, y: -pivot.y)
    }
    mutating func move(to point: CGPoint) {
        if handle == .rotation {
            let dx = point.x - pivot.x, dy = point.y - pivot.y
            guard hypot(dx, dy) > 0.001 else { return }
            radians = atan2(dy, dx) - atan2(start.y - pivot.y, start.x - pivot.x)
        } else {
            let sign: CGFloat = handle == .start ? -1 : 1
            scale = min(5, max(0.2, 1 + sign * (point.x - start.x) / max(0.001, box.width)))
        }
    }
}
