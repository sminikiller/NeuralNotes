import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit
import NeuralNotesCore

@MainActor
final class CanvasDrawingAssistant: NSObject, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private let monitor = DrawingTouchMonitor()
    private var points: [StrokeSample] = []
    private var pageID: UUID?
    private var anchor = CGPoint.zero
    private var holdTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private let preview = CAShapeLayer()
    private let previousInk = UIImageView()
    private var before = PKDrawing()
    private var held = false
    private var markerSession: MarkerEraseSession?
    private var guiding = false
    private var guideEdge = 1.0
    private var beganAt = Date()
    private var connectionIndex = ShapeConnectionIndex()
    private var snapHint: String?

    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        super.init()
        preview.fillColor = UIColor.clear.cgColor; preview.lineCap = .round; preview.lineJoin = .round
        previousInk.isUserInteractionEnabled = false; previousInk.contentMode = .scaleToFill
        monitor.owner = self; monitor.delegate = self
        monitor.cancelsTouchesInView = false; monitor.delaysTouchesBegan = false; monitor.delaysTouchesEnded = false
        monitor.requiresExclusiveTouchType = false
        monitor.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue), NSNumber(value: UITouch.TouchType.direct.rawValue)]
        host.canvas.addGestureRecognizer(monitor)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let model, model.hasLease, !model.loading, !model.navigating, model.editingTextID == nil else { return false }
        if model.audio?.replayInk == true && model.audio?.playingSessionID != nil { return false }
        let enabled = model.tool == .shape || (model.tool == .eraser && model.writingOptions.markerOnly) || ((model.tool == .pen || model.tool == .marker) && (model.rulerActive || model.recognitionMode != .off))
        return enabled && (touch.type == .pencil || (touch.type == .direct && (model.fingerDrawing || model.tool == .shape)))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func begin(_ touch: UITouch) {
        guard let host else { return }
        begin(at: touch.location(in: host.surface))
    }
    func begin(at: CGPoint) {
        model?.finishInkGesture()
        cancel()
        guard let host, let model, let page = model.page else { return }
        guard host.surface.bounds.contains(at) else { return }
        pageID = page.id; before = host.canvas.drawing; anchor = at
        points = [StrokeSample(x: Double(at.x), y: Double(at.y))]
        beganAt = Date(); snapHint = nil
        let connections = (page.shapes ?? []).filter { !(page.lockedObjects ?? []).contains($0.id) }.flatMap { shape in
            let local = [StrokeSample(x: shape.x + shape.width / 2, y: shape.y),
                .init(x: shape.x + shape.width, y: shape.y + shape.height / 2),
                .init(x: shape.x + shape.width / 2, y: shape.y + shape.height),
                .init(x: shape.x, y: shape.y + shape.height / 2)]
            return local.map { ShapeGeometry.rotate($0, shape: shape) }
        }
        connectionIndex = ShapeConnectionIndex(points: connections)
        if model.tool == .shape, model.shapeKind == .line || model.shapeKind == .arrow,
           let snapped = connection(near: points[0]) { points[0] = snapped }
        if model.rulerActive && (model.tool == .pen || model.tool == .marker) {
            guideEdge = model.rulerGuide.edge(nearest: points[0])
            guard let projected = model.rulerGuide.project(points[0], edge: guideEdge, width: page.width, height: page.height) else { pageID = nil; return }
            points = [projected]; model.strokeBegan(); guiding = true; model.drawingShape = true
        }
        if model.tool == .shape || model.tool == .eraser { model.drawingShape = true }
        if model.tool == .eraser { markerSession = MarkerEraseSession(model: model); markerSession?.append(points) }
    }
    func move(_ touch: UITouch, event: UIEvent) {
        guard let host else { return }
        move(samples: (event.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: host.surface) })
    }
    func move(samples: [CGPoint]) {
        guard let host, let model, model.page?.id == pageID, let page = model.page else { return }
        if guiding {
            for point in samples {
                if let projected = model.rulerGuide.project(StrokeSample(x: point.x, y: point.y), edge: guideEdge, width: page.width, height: page.height) { points.append(projected) }
            }
            if points.count > 2000 { points = points.enumerated().filter { $0.offset % 2 == 0 || $0.offset == points.count - 1 }.map(\.element) }
            drawPreview(.line); return
        }
        // Recognition is latched until lift. Coalesced final samples and tiny
        // Pencil motion must never cancel an already confirmed preview.
        guard !held else { return }
        for raw in samples {
            let p = CGPoint(x: max(0, min(CGFloat(page.width), raw.x)), y: max(0, min(CGFloat(page.height), raw.y)))
            points.append(StrokeSample(x: Double(p.x), y: Double(p.y)))
        }
        if points.count > 2000 { points = points.enumerated().filter { $0.offset % 2 == 0 || $0.offset == points.count - 1 }.map(\.element) }
        if model.tool == .eraser {
            markerSession?.append(samples.map { StrokeSample(x: Double($0.x), y: Double($0.y)) }); return
        }
        if model.tool == .shape { drawPreview(model.shapeKind); return }
        guard model.recognitionMode == .hold else { return }
        guard let at = samples.last else { return }
        if hypot(at.x - anchor.x, at.y - anchor.y) > max(1.5, 3 / host.canvas.zoomScale) {
            anchor = at; holdTask?.cancel()
            holdTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                self?.recognizeHold()
            }
        }
    }
    func end(cancelled: Bool) {
        holdTask?.cancel(); holdTask = nil
        guard let model else { cancel(); return }
        if guiding {
            if cancelled { model.cancelGuidedInk(before) }
            else {
                let width = model.tool == .marker ? max(12, model.thickness * 5) : model.thickness
                let controls = points.enumerated().map { index, point in
                    PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: Double(index) * 0.01,
                        size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                if controls.count > 1 {
                    let ink = PKInk(model.tool == .marker ? .marker : model.writingOptions.pen.native, color: PaperInk.color(model.ink))
                    let stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
                    model.canvas.drawing = PKDrawing(strokes: before.strokes + [stroke])
                } else { model.cancelGuidedInk(before) }
                model.drawingShape = false; model.strokeEnded(); model.finishInkGesture()
            }
            guiding = false; cancel(); return
        }
        if model.tool == .eraser {
            model.drawingShape = false
            markerSession?.finish(cancelled: cancelled); markerSession = nil
            cancel(); return
        }
        if model.tool == .shape {
            model.drawingShape = false
            if !cancelled, model.page?.id == pageID, let first = points.first, let last = points.last {
                model.addDraggedShape(model.shapeKind, from: first, to: connection(near: last) ?? last)
            }
            cancel(); return
        }
        if cancelled { model.pendingHeldShape = nil; model.pendingShapeRecognition = nil; finishPreview() }
        else if held {
            // The final PencilKit drawing arrives separately. The model keeps
            // this preview until it has replaced exactly that new stroke.
            cleanupTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                self?.finishPreview()
            }
        } else if model.recognitionMode == .automatic { recognizeAtLift() }
        pageID = nil
    }
    func recognizeHold() {
        guard let host, let model, let page = model.page, page.id == pageID,
              model.recognitionMode == .hold, !model.rulerActive, model.tool == .pen || model.tool == .marker,
              let result = ShapeRecognizer.recognize(points, enabled: model.tool == .marker ? [.line] : model.shapePreferences.kinds) else { return }
        let kind = result.shape.kind
        held = true; model.pendingHeldShape = (page.id, kind, points); model.pendingShapeRecognition = result
        previousInk.image = PaperInk.image(before, from: CGRect(x: 0, y: 0, width: page.width, height: page.height),
            scale: min(2, 1600 / max(CGFloat(page.width), CGFloat(page.height))))
        previousInk.frame = host.surface.frame; host.addSubview(previousInk)
        host.canvas.layer.opacity = 0
        drawPreview(kind)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func drawPreview(_ kind: ShapeKind) {
        guard let host, let model else { return }
        let samples = model.tool == .shape ? [points.first, points.last].compactMap { $0 } : points
        let path: UIBezierPath
        if guiding {
            path = UIBezierPath()
            for (i, p) in points.enumerated() {
                if i == 0 { path.move(to: CGPoint(x: p.x, y: p.y)) } else { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
            }
        } else if model.tool == .shape, let a = samples.first, let b = samples.last,
                  let shape = model.shapeForDrag(kind, from: a, to: connection(near: b) ?? b) {
            path = UIBezierPath(cgPath: ShapePathRendering.path(ShapeGeometry.path(for: shape)))
            for arrow in ShapeGeometry.arrowPaths(for: shape) { path.append(UIBezierPath(cgPath: ShapePathRendering.path(arrow))) }
            let snap = ShapeSnapping.drag(kind: kind, start: a, end: b)
            let hint: String? = snap.proportionsSnapped ? "Proporzioni 1:1" : (snap.angleSnapped ? "Angolo agganciato" : nil)
            if let hint, hint != snapHint { host.showPageInputHint(hint); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            snapHint = hint
            preview.fillColor = shape.fill.map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: shape.fillOpacity ?? 0.25).cgColor }
            preview.lineDashPattern = (shape.dash ?? .solid).lengths(width: shape.lineWidth * host.canvas.zoomScale).map { NSNumber(value: $0) }
        } else { path = PreciseStrokeGeometry.path(kind: kind, points: samples); preview.fillColor = UIColor.clear.cgColor; preview.lineDashPattern = nil }
        let converted = UIBezierPath(cgPath: path.cgPath)
        var transform = CGAffineTransform(scaleX: host.canvas.zoomScale, y: host.canvas.zoomScale)
        transform.tx = host.surface.frame.minX; transform.ty = host.surface.frame.minY
        converted.apply(transform)
        preview.path = converted.cgPath; preview.strokeColor = PaperInk.color(model.ink).cgColor
        preview.lineWidth = CGFloat(model.tool == .marker ? max(12, model.thickness * 5) : model.thickness) * host.canvas.zoomScale
        preview.opacity = model.tool == .marker ? 0.4 : 1
        if preview.superlayer == nil { host.layer.addSublayer(preview) }
    }
    func finishPreview() {
        cleanupTask?.cancel(); cleanupTask = nil
        host?.canvas.layer.opacity = 1; previousInk.removeFromSuperview(); previousInk.image = nil
        preview.removeFromSuperlayer(); preview.path = nil; held = false
    }
    func cancel() {
        if guiding { model?.cancelGuidedInk(before); guiding = false }
        markerSession?.finish(cancelled: true); markerSession = nil
        holdTask?.cancel(); holdTask = nil; finishPreview()
        model?.pendingHeldShape = nil; model?.pendingShapeRecognition = nil; model?.pendingAutomaticRecognition = false; model?.drawingShape = false
        points = []; pageID = nil
    }
    private func connection(near point: StrokeSample) -> StrokeSample? {
        guard let host, model?.tool == .shape, model?.shapeKind == .line || model?.shapeKind == .arrow else { return nil }
        return connectionIndex.nearest(point, zoom: host.canvas.zoomScale)
    }
    private func recognizeAtLift() {
        guard let model, let pageID, !model.rulerActive, let first = points.first else { return }
        let nearWriting = before.strokes.suffix(12).contains { stroke in
            let box = stroke.renderBounds
            return Date().timeIntervalSince(stroke.path.creationDate) < 8 &&
                box.insetBy(dx: -20, dy: -20).contains(CGPoint(x: first.x, y: first.y))
        }
        let marker = model.tool == .marker
        let duration = Date().timeIntervalSince(beganAt)
        let context = ShapeRecognitionContext(duration: marker ? max(0.18, duration) : duration, nearWriting: !marker && nearWriting)
        guard let result = ShapeRecognizer.recognize(points, mode: .automatic,
            enabled: model.tool == .marker ? [.line] : model.shapePreferences.kinds, context: context) else { return }
        model.pendingHeldShape = (pageID, result.shape.kind, points)
        model.pendingShapeRecognition = result; model.pendingAutomaticRecognition = true
    }
}

@MainActor
private final class DrawingTouchMonitor: UIGestureRecognizer {
    weak var owner: CanvasDrawingAssistant?
    private weak var tracked: UITouch?
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, touches.count == 1, let touch = touches.first else { owner?.cancel(); state = .cancelled; return }
        tracked = touch; owner?.begin(touch); state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        owner?.move(touch, event: event); state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        owner?.move(touch, event: event); owner?.end(cancelled: false); tracked = nil; state = .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { owner?.end(cancelled: true); tracked = nil; state = .cancelled }
    override func reset() { tracked = nil; super.reset() }
}
