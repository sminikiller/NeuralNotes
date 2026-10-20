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
        let enabled = model.tool == .shape || (model.tool == .eraser && model.writingOptions.markerOnly) || ((model.tool == .pen || model.tool == .marker) && model.currentWorkspace.holdShapes && !model.rulerActive)
        return enabled && (touch.type == .pencil || (touch.type == .direct && (model.fingerDrawing || model.tool == .shape)))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func begin(_ touch: UITouch) {
        guard let host else { return }
        begin(at: touch.location(in: host.surface))
    }
    func begin(at: CGPoint) {
        cancel()
        guard let host, let model, let page = model.page else { return }
        guard host.surface.bounds.contains(at) else { return }
        pageID = page.id; before = host.canvas.drawing; anchor = at
        points = [StrokeSample(x: Double(at.x), y: Double(at.y))]
        if model.tool == .shape || model.tool == .eraser { model.drawingShape = true }
        if model.tool == .eraser { markerSession = MarkerEraseSession(model: model); markerSession?.append(points) }
    }
    func move(_ touch: UITouch, event: UIEvent) {
        guard let host else { return }
        move(samples: (event.coalescedTouches(for: touch) ?? [touch]).map { $0.location(in: host.surface) })
    }
    func move(samples: [CGPoint]) {
        guard let host, let model, model.page?.id == pageID, let page = model.page else { return }
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
        guard let at = samples.last else { return }
        if hypot(at.x - anchor.x, at.y - anchor.y) > max(1.5, 3 / host.canvas.zoomScale) {
            anchor = at; holdTask?.cancel()
            holdTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                self?.recognizeHold()
            }
        }
    }
    func end(cancelled: Bool) {
        holdTask?.cancel(); holdTask = nil
        guard let model else { cancel(); return }
        if model.tool == .eraser {
            model.drawingShape = false
            markerSession?.finish(cancelled: cancelled); markerSession = nil
            cancel(); return
        }
        if model.tool == .shape {
            model.drawingShape = false
            if !cancelled, model.page?.id == pageID, let first = points.first, let last = points.last {
                model.addDraggedShape(model.shapeKind, from: first, to: last)
            }
            cancel(); return
        }
        if cancelled { model.pendingHeldShape = nil; finishPreview() }
        else if held {
            // The final PencilKit drawing arrives separately. The model keeps
            // this preview until it has replaced exactly that new stroke.
            cleanupTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                self?.finishPreview()
            }
        }
        pageID = nil
    }
    func recognizeHold() {
        guard let host, let model, let page = model.page, page.id == pageID,
              model.currentWorkspace.holdShapes, !model.rulerActive, model.tool == .pen || model.tool == .marker,
              let kind = HeldShapeRecognition.recognize(points) else { return }
        held = true; model.pendingHeldShape = (page.id, kind, points)
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
        let path = PreciseStrokeGeometry.path(kind: kind, points: samples)
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
        markerSession?.finish(cancelled: true); markerSession = nil
        holdTask?.cancel(); holdTask = nil; finishPreview()
        model?.pendingHeldShape = nil; model?.drawingShape = false
        points = []; pageID = nil
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

@MainActor
enum PreciseStrokeGeometry {
    static func path(kind: ShapeKind, points: [StrokeSample]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let a = points.first, let b = points.last else { return path }
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = CGRect(x: xs.min() ?? a.x, y: ys.min() ?? a.y, width: max(1, (xs.max() ?? b.x) - (xs.min() ?? a.x)), height: max(1, (ys.max() ?? b.y) - (ys.min() ?? a.y)))
        switch kind {
        case .line, .arrow:
            path.move(to: CGPoint(x: a.x, y: a.y)); path.addLine(to: CGPoint(x: b.x, y: b.y))
            if kind == .arrow {
                let angle = atan2(b.y - a.y, b.x - a.x)
                for delta in [-Double.pi / 6, Double.pi / 6] {
                    path.move(to: CGPoint(x: b.x, y: b.y)); path.addLine(to: CGPoint(x: b.x - 14 * cos(angle + delta), y: b.y - 14 * sin(angle + delta)))
                }
            }
        case .ellipse: return UIBezierPath(ovalIn: rect)
        case .rectangle: return UIBezierPath(rect: rect)
        }
        return path
    }
    static func stroke(kind: ShapeKind, points: [StrokeSample], original: PKStroke) -> PKStroke {
        let path = path(kind: kind, points: points)
        var locations: [CGPoint] = []
        // Sample the exact geometry into native PencilKit vectors. No raster
        // replacement is stored in the notebook or its vector PDF export.
        let bounds = path.bounds
        if kind == .line, let a = points.first, let b = points.last {
            locations = [CGPoint(x: a.x, y: a.y), CGPoint(x: b.x, y: b.y)]
        } else if kind == .rectangle {
            let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.minY)]
            for (a, b) in zip(corners, corners.dropFirst()) {
                let count = max(2, min(400, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 4))))
                for i in 0..<count {
                    let t = CGFloat(i) / CGFloat(count)
                    locations.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            locations.append(corners[0])
        } else {
            locations = (0...120).map { i in
                let angle = Double(i) * 2 * .pi / 120
                return CGPoint(x: bounds.midX + bounds.width / 2 * CGFloat(cos(angle)), y: bounds.midY + bounds.height / 2 * CGFloat(sin(angle)))
            }
        }
        let sample = original.path.interpolatedPoints(by: .distance(8)).map { $0 }.first
        let size = sample?.size ?? CGSize(width: 3, height: 3)
        let controls = locations.enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i) * 0.02, size: size, opacity: sample?.opacity ?? 1,
                force: sample?.force ?? 1, azimuth: sample?.azimuth ?? 0, altitude: sample?.altitude ?? .pi / 2)
        }
        return PKStroke(ink: original.ink, path: PKStrokePath(controlPoints: controls, creationDate: original.path.creationDate))
    }
}

@MainActor
extension EditorViewModel {
    func addDraggedShape(_ kind: ShapeKind, from a: StrokeSample, to b: StrokeSample) {
        guard let shape = ShapeElement.dragged(kind: kind, from: a, to: b, color: InkColor(ink), lineWidth: thickness) else { return }
        mutatePage("Traccia \(kind.title)") { $0.shapes = ($0.shapes ?? []) + [shape] }
        selectedObjectID = shape.id; rememberPalette()
    }
    func applyHeldShapeIfNeeded() -> Bool {
        defer { pendingHeldShape = nil }
        guard currentWorkspace.holdShapes, tool == .pen || tool == .marker,
              let held = pendingHeldShape, held.page == page?.id, let bytes = editBeforeGesture?.drawing,
              let previous = try? PKDrawing(data: bytes), canvas.drawing.strokes.count == previous.strokes.count + 1,
              let original = canvas.drawing.strokes.last else { return false }
        let corrected = PreciseStrokeGeometry.stroke(kind: held.kind, points: held.samples, original: original)
        canvas.drawing = PKDrawing(strokes: previous.strokes + [corrected]); return true
    }
}
