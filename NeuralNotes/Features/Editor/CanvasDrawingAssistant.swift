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
    private var wordSession: MarkerWordSession?
    private var protractorSession: ProtractorInkSession?
    private var guiding = false
    private var guideEdge = 1.0
    private var beganAt = Date()
    private var connectionIndex = ShapeConnectionIndex()
    private var shapeSnapEngine: SnapEngine?
    private var snapHint: String?
    private(set) var locksPageNavigation = false

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
        let enabled = model.tool == .shape || model.markerCustomInput || (model.tool == .eraser && model.writingOptions.markerOnly) || ((model.tool == .pen || model.tool == .marker) && (model.rulerActive || model.protractorActive || model.recognitionMode != .off))
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
        if let session = ProtractorInkSession(host: host, model: model, start: points[0]) {
            protractorSession = session; lockPageNavigation(); return
        }
        if model.markerCustomInput {
            wordSession = MarkerWordSession(host: host, model: model); wordSession?.move([at]); return
        }
        var connections: [StrokeSample] = []
        if model.tool == .shape, model.shapeKind == .line || model.shapeKind == .arrow {
            let locked = Set(page.lockedObjects ?? [])
            connections = (page.shapes ?? []).filter { !locked.contains($0.id) }.flatMap { ShapeGeometry.connectionPoints($0) }
        }
        connectionIndex = ShapeConnectionIndex(points: connections)
        shapeSnapEngine = model.tool == .shape ? model.snapEngine(excluding: []) : nil
        if model.tool == .shape, model.shapeKind == .line || model.shapeKind == .arrow,
           let snapped = connection(near: points[0]) { points[0] = snapped }
        if model.tool == .shape { points[0] = shapeEndpoint(points[0]).0 }
        if model.rulerActive && (model.tool == .pen || model.tool == .marker) {
            guideEdge = model.rulerGuide.edge(nearest: points[0])
            guard let projected = model.rulerGuide.project(points[0], edge: guideEdge, width: page.width, height: page.height) else { pageID = nil; return }
            points = [projected]; model.strokeBegan(); guiding = true; model.drawingShape = true
            model.guideReadout = nil
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
        if let protractorSession { protractorSession.move(samples); return }
        if let wordSession {
            if !held { wordSession.move(samples) }
            if wordSession.selectsWords { return }
        }
        if guiding {
            for point in samples {
                if let projected = model.rulerGuide.project(StrokeSample(x: point.x, y: point.y), edge: guideEdge, width: page.width, height: page.height) { points.append(projected) }
            }
            if points.count > 2000 { points = points.enumerated().filter { $0.offset % 2 == 0 || $0.offset == points.count - 1 }.map(\.element) }
            if let first = points.first, let last = points.last {
                let distance = hypot(last.x - first.x, last.y - first.y)
                let angle = atan2(last.y - first.y, last.x - first.x) * 180 / .pi
                model.guideReadout = String(format: "%.2f cm · %.0f°", distance / 72 * 2.54, angle)
                host.rulerGuide?.update()
            }
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
        if model.tool == .shape {
            if shapeHasMoved { lockPageNavigation() }
            drawPreview(model.shapeKind); return
        }
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
    func end(cancelled: Bool, modifierActive: Bool? = nil) {
        holdTask?.cancel(); holdTask = nil
        guard let model else { cancel(); return }
        if let session = protractorSession {
            protractorSession = nil; session.finish(cancelled: cancelled); cancel(); return
        }
        if let session = wordSession {
            if !session.selectsWords, !held, !cancelled, model.recognitionMode == .automatic { recognizeAtLift() }
            wordSession = nil; session.finish(cancelled: cancelled); cancel(); return
        }
        if guiding {
            if cancelled { model.cancelGuidedInk(before) }
            else {
                let width = model.tool == .marker ? model.markerWidth : model.thickness
                let controls = points.enumerated().map { index, point in
                    PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: Double(index) * 0.01,
                        size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                if controls.count > 1 {
                    let ink = PKInk(model.tool == .marker ? .marker : model.writingOptions.pen.native, color: PaperInk.color(model.ink))
                    let stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
                    model.installNativeInk(PKDrawing(strokes: before.strokes + [stroke]))
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
                let endpoint = shapeEndpoint(last, modifierActive: modifierActive)
                model.addDraggedShape(model.shapeKind, from: first, to: endpoint.0, preserveEnd: endpoint.1)
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
              !held, model.recognitionMode == .hold, !model.rulerActive, model.tool == .pen || model.tool == .marker,
              let result = ShapeRecognizer.recognize(points, enabled: model.tool == .marker ? [.line] : model.shapePreferences.kinds) else { return }
        let kind = result.shape.kind
        held = true; model.pendingHeldShape = (page.id, kind, points); model.pendingShapeRecognition = result
        previousInk.image = DocumentServices.image(page: page, drawing: before, workspace: model.workspace, maxDimension: 1600)
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
                  let shape = previewShape(kind, start: a, end: b) {
            path = UIBezierPath(cgPath: ShapePathRendering.path(ShapeGeometry.path(for: shape)))
            for arrow in ShapeGeometry.arrowPaths(for: shape) { path.append(UIBezierPath(cgPath: ShapePathRendering.path(arrow))) }
            let snap = ShapeSnapping.drag(kind: kind, start: a, end: b)
            let hint: String? = connection(near: b) != nil ? "Estremo agganciato" : (snap.proportionsSnapped ? "Proporzioni 1:1" : (snap.angleSnapped ? "Angolo agganciato" : nil))
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
        preview.lineWidth = CGFloat(model.tool == .marker ? model.markerWidth : model.thickness) * host.canvas.zoomScale
        preview.opacity = model.tool == .marker ? 0.4 : 1
        if preview.superlayer == nil { host.layer.addSublayer(preview) }
    }
    func finishPreview() {
        cleanupTask?.cancel(); cleanupTask = nil
        host?.canvas.layer.opacity = 1; previousInk.removeFromSuperview(); previousInk.image = nil
        preview.removeFromSuperlayer(); preview.path = nil; held = false
    }
    func cancel() {
        if let session = protractorSession { protractorSession = nil; session.finish(cancelled: true) }
        if let session = wordSession { wordSession = nil; session.finish(cancelled: true) }
        if guiding { model?.cancelGuidedInk(before); guiding = false }
        markerSession?.finish(cancelled: true); markerSession = nil
        holdTask?.cancel(); holdTask = nil; finishPreview()
        model?.pendingHeldShape = nil; model?.pendingShapeRecognition = nil; model?.pendingAutomaticRecognition = false; model?.drawingShape = false
        points = []; pageID = nil
        shapeSnapEngine = nil; host?.snapGuides?.show([])
        if locksPageNavigation { locksPageNavigation = false; host?.canvas.panGestureRecognizer.isEnabled = true }
    }
    private var shapeHasMoved: Bool {
        guard points.count > 1, let last = points.last, let host else { return false }
        return hypot(last.x - anchor.x, last.y - anchor.y) >= 4 / max(0.05, host.canvas.zoomScale)
    }
    private func lockPageNavigation() {
        locksPageNavigation = true; host?.canvas.panGestureRecognizer.isEnabled = false
    }
    /// A two-finger gesture begun before drawing must remain page navigation.
    /// Once the primary pointer is drawing, extra fingers only modify snapping.
    func additionalTouchIsModifier(primaryIsPencil: Bool) -> Bool {
        guard model?.tool == .shape, primaryIsPencil || shapeHasMoved else { return false }
        lockPageNavigation(); return true
    }
    private func connection(near point: StrokeSample) -> StrokeSample? {
        guard let host, !monitor.snapModifierActive, !monitor.modifierFlags.contains(.alternate), model?.snapPreferences.objectsEnabled == true,
              model?.tool == .shape, model?.shapeKind == .line || model?.shapeKind == .arrow else { return nil }
        return connectionIndex.nearest(point, zoom: host.canvas.zoomScale)
    }
    private func shapeEndpoint(_ point: StrokeSample, modifierActive: Bool? = nil) -> (StrokeSample, Bool) {
        guard let host, let model else { return (point, false) }
        let suspended = (modifierActive ?? monitor.snapModifierActive) || monitor.modifierFlags.contains(.alternate)
        if suspended { host.snapGuides?.show([]); return (point, true) }
        if let connected = connection(near: point) { host.snapGuides?.show([]); return (connected, true) }
        guard let engine = shapeSnapEngine else { return (point, false) }
        var preferences = model.snapPreferences; preferences.objects = false
        let result = engine.snapPoint(point, zoom: host.canvas.zoomScale, preferences: preferences)
        host.snapGuides?.show(result.guides)
        return (result.point, result.snapped)
    }
    private func previewShape(_ kind: ShapeKind, start: StrokeSample, end: StrokeSample) -> ShapeElement? {
        let endpoint = shapeEndpoint(end)
        return model?.shapeForDrag(kind, from: start, to: endpoint.0, preserveEnd: endpoint.1)
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
    private(set) var snapModifierActive = false
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Once drawing a shape, a second finger is only a snap modifier.
        // It must not cancel the draft or replace its primary Pencil/finger.
        if let tracked {
            snapModifierActive = SnapTouchModifiers.active(primary: tracked, event: event)
            if owner?.additionalTouchIsModifier(primaryIsPencil: tracked.type == .pencil) == true { return }
            owner?.end(cancelled: true); self.tracked = nil; state = .cancelled; return
        }
        guard touches.count == 1, let touch = touches.first else { owner?.cancel(); state = .cancelled; return }
        tracked = touch; snapModifierActive = SnapTouchModifiers.active(primary: touch, event: event)
        owner?.begin(touch); state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        snapModifierActive = SnapTouchModifiers.active(primary: touch, event: event)
        owner?.move(touch, event: event); state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        snapModifierActive = SnapTouchModifiers.active(primary: touch, event: event, includingEnded: true)
        owner?.move(touch, event: event); owner?.end(cancelled: false, modifierActive: snapModifierActive); tracked = nil; state = .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { owner?.end(cancelled: true); tracked = nil; state = .cancelled }
    override func reset() { tracked = nil; snapModifierActive = false; super.reset() }
}
