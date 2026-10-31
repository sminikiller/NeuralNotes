import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
final class CanvasInteraction: NSObject, UIGestureRecognizerDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private let outline = CAShapeLayer(), handle = CAShapeLayer(), marquee = CAShapeLayer()
    /// Words under a Lens stroke, highlighted like a marker while the stroke goes on.
    private let wordHighlight = CAShapeLayer()
    /// The picture of the object being dragged.
    private var dragPreview: CALayer?
    private var before: EditorContentState?
    private var start = CGPoint.zero
    private var original: [UUID: CGRect] = [:]
    private var resizing = false
    private let inkID = UUID()
    private var originalDrawing: PKDrawing?
    private var snapEngine: SnapEngine?
    private var originalVisualBounds: CGRect?
    private var selectionTrace: [CGPoint] = []
    /// A Lens note dragged while the Lens tool is active.
    private var movingLensNote: UUID?
    private let fitTap = UITapGestureRecognizer()
    private let objectTap = UITapGestureRecognizer()
    private let pointerFitTap = UITapGestureRecognizer()
    private let labelTap = UITapGestureRecognizer()
    private let undoTap = UITapGestureRecognizer(), redoTap = UITapGestureRecognizer()
    private let nextSwipe = UISwipeGestureRecognizer(), previousSwipe = UISwipeGestureRecognizer()
    private let nextVerticalSwipe = UISwipeGestureRecognizer(), previousVerticalSwipe = UISwipeGestureRecognizer()
    private var pageSwipes: [UISwipeGestureRecognizer] { [nextSwipe, previousSwipe, nextVerticalSwipe, previousVerticalSwipe] }

    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model
        super.init()
        outline.fillColor = UIColor.clear.cgColor; outline.strokeColor = UIColor.systemTeal.cgColor; outline.lineWidth = 2
        handle.fillColor = UIColor.systemTeal.cgColor
        marquee.fillColor = UIColor.systemTeal.withAlphaComponent(0.1).cgColor
        marquee.strokeColor = UIColor.systemTeal.cgColor; marquee.lineDashPattern = [5, 4]
        wordHighlight.fillColor = UIColor.systemYellow.withAlphaComponent(0.38).cgColor; wordHighlight.strokeColor = nil
        for layer in [wordHighlight, outline, handle, marquee] { host.layer.addSublayer(layer) }
        let tap = objectTap
        tap.addTarget(self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false; tap.delaysTouchesBegan = false
        fitTap.addTarget(self, action: #selector(fitPage(_:)))
        fitTap.numberOfTapsRequired = 2
        fitTap.name = "pageFitGesture"
        fitTap.numberOfTouchesRequired = model.fingerDrawing ? 2 : 1
        fitTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pointerFitTap.addTarget(self, action: #selector(fitPage(_:))); pointerFitTap.numberOfTapsRequired = 2
        pointerFitTap.name = "pageFitGesture"
        pointerFitTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        for gesture in [fitTap, pointerFitTap] {
            gesture.cancelsTouchesInView = false; gesture.delaysTouchesBegan = false
            gesture.requiresExclusiveTouchType = false
            gesture.delegate = self; host.canvas.addGestureRecognizer(gesture)
        }
        tap.require(toFail: fitTap)
        tap.require(toFail: pointerFitTap)
        labelTap.addTarget(self, action: #selector(fitPage(_:))); labelTap.numberOfTapsRequired = 2
        labelTap.name = "diagramLabelGesture"
        labelTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        labelTap.delegate = self; labelTap.cancelsTouchesInView = false; host.canvas.addGestureRecognizer(labelTap)
        tap.require(toFail: labelTap)
        undoTap.numberOfTouchesRequired = 2; redoTap.numberOfTouchesRequired = 3
        undoTap.addTarget(self, action: #selector(historyTap(_:))); redoTap.addTarget(self, action: #selector(historyTap(_:)))
        undoTap.require(toFail: fitTap)
        for gesture in [undoTap, redoTap] {
            gesture.delegate = self; gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            host.canvas.addGestureRecognizer(gesture)
        }
        nextSwipe.direction = .left; previousSwipe.direction = .right
        nextVerticalSwipe.direction = .up; previousVerticalSwipe.direction = .down
        for swipe in pageSwipes {
            swipe.addTarget(self, action: #selector(turnPage(_:))); swipe.delegate = self
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            host.canvas.addGestureRecognizer(swipe)
        }
        let pan = SnapPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 2
        for gesture in [tap as UIGestureRecognizer, pan] {
            gesture.delegate = self
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            host.addGestureRecognizer(gesture)
        }
        host.canvas.panGestureRecognizer.require(toFail: pan)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func resetForPageChange() {
        host?.diagramPreview?.reset()
        dragPreview?.removeFromSuperlayer(); dragPreview = nil
        for layer in [outline, handle, marquee, wordHighlight] {
            layer.path = nil; layer.setAffineTransform(.identity)
        }
        before = nil; original = [:]; originalDrawing = nil
        movingLensNote = nil; selectionTrace = []
        snapEngine = nil; originalVisualBounds = nil; host?.snapGuides?.show([])
    }

    func refresh() {
        let touches = model?.fingerDrawing == true ? 2 : 1
        if fitTap.numberOfTouchesRequired != touches { fitTap.numberOfTouchesRequired = touches }
        for swipe in pageSwipes {
            let horizontal = swipe === nextSwipe || swipe === previousSwipe
            let enabled = horizontal && model?.pageNavigation == .horizontal
            if swipe.isEnabled != enabled { swipe.isEnabled = enabled }
            if swipe.numberOfTouchesRequired != touches { swipe.numberOfTouchesRequired = touches }
        }
        guard let host, let model, model.tool == .objects else { outline.path = nil; handle.path = nil; return }
        let path = UIBezierPath()
        for id in model.selectedIDs {
            if let shape = model.page?.shapes?.first(where: { $0.id == id }) {
                let corners = [StrokeSample(x: shape.x, y: shape.y), .init(x: shape.x + shape.width, y: shape.y),
                    .init(x: shape.x + shape.width, y: shape.y + shape.height), .init(x: shape.x, y: shape.y + shape.height)]
                let box = UIBezierPath()
                for (index, corner) in corners.enumerated() {
                    let rotated = ShapeGeometry.rotate(corner, shape: shape)
                    let at = host.surface.convert(CGPoint(x: rotated.x, y: rotated.y), to: host)
                    if index == 0 { box.move(to: at) } else { box.addLine(to: at) }
                }
                box.close(); path.append(box)
            } else if let rect = objectRect(id) { path.append(UIBezierPath(rect: host.surface.convert(rect, to: host))) }
        }
        if model.selectionIncludesInk { path.append(UIBezierPath(rect: host.surface.convert(model.selectedInkBounds, to: host))) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outline.path = path.cgPath
        if model.selectedIDs.count == 1, !model.selectionIncludesInk, let id = model.selectedObjectID,
           model.page?.shapes?.contains(where: { $0.id == id }) != true,
           model.page?.connectors?.contains(where: { $0.id == id }) != true,
           model.page?.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed != true, let rect = objectRect(id) {
            let display = host.surface.convert(rect, to: host)
            handle.path = UIBezierPath(ovalIn: CGRect(x: display.maxX - 7, y: display.maxY - 7, width: 14, height: 14)).cgPath
        } else { handle.path = nil }
        CATransaction.commit()
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let model, let host, !model.loading, !model.navigating else { return false }
        if gesture === labelTap { return model.tool == .objects && model.editingTextID == nil }
        if gesture === undoTap || gesture === redoTap { return model.hasLease && !model.hasActiveStroke && model.editingTextID == nil }
        if gesture is UITapGestureRecognizer, gesture !== fitTap, gesture !== pointerFitTap,
           model.checklistHit(at: gesture.location(in: host.surface)) != nil { return true }
        if gesture is UITapGestureRecognizer, gesture !== fitTap, gesture !== pointerFitTap,
           model.tapeHit(at: gesture.location(in: host.surface)) != nil { return true }
        // A Lens note opens from its 💡 and closes from its round control with any tool.
        if gesture === objectTap, let note = model.lensNoteHit(at: gesture.location(in: host.surface), tolerance: lensTolerance), note.part != .body { return true }
        if gesture === fitTap || gesture === pointerFitTap { return model.editingTextID == nil }
        if pageSwipes.contains(where: { $0 === gesture }) {
            return model.hasLease && !model.interactionBusy && host.canvas.zoomScale <= host.canvas.minimumZoomScale * 1.05
        }
        if gesture is UIPanGestureRecognizer {
            if model.selectionPageDragMode { return false }
            if model.tool == .lens { return true }
            return model.tool == .objects && (model.selectRectangle || model.selectFreehand || hit(gesture.location(in: host.surface)) != nil)
        }
        if model.pageNavigation == .vertical, host.flow?.page(at: gesture.location(in: host)) != model.page?.id { return true }
        return model.tool == .objects || model.tool == .audioLink || model.tool == .text || model.tool == .lens
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let handles = host?.shapeHandles, let touched = touch.view,
           touched !== handles, touched.isDescendant(of: handles) { return false }
        if let handles = host?.diagramHandles, let touched = touch.view,
           touched !== handles, touched.isDescendant(of: handles) { return false }
        if touch.type == .pencil, gesture is UITapGestureRecognizer,
           model?.tool == .pen || model?.tool == .marker || model?.tool == .eraser { return false }
        if pageSwipes.contains(where: { $0 === gesture }) && touch.type != .direct { return false }
        if let input = host?.textInput?.view, let touched = touch.view, touched.isDescendant(of: input) { return false }
        if let bar = host?.lensBar, let touched = touch.view, touched.isDescendant(of: bar) { return false }
        return true
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // PencilKit's internal scroll/tap recognizers must not swallow our fit
        // or page-turn gesture. Drawing input itself remains Pencil-only.
        gesture === objectTap || gesture === fitTap || gesture === pointerFitTap || gesture === labelTap || pageSwipes.contains(where: { $0 === gesture })
    }

    @objc private func turnPage(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        let delta = gesture.direction == .left || gesture.direction == .up ? 1 : -1
        Task { await model?.turnPage(delta) }
    }

    @objc private func fitPage(_ gesture: UITapGestureRecognizer) {
        if let host, let model, model.tool == .objects, let id = diagramLabelHit(gesture.location(in: host.surface)),
           model.page?.shapes?.contains(where: { $0.id == id }) == true || model.page?.connectors?.contains(where: { $0.id == id }) == true {
            model.editDiagramLabel(id); return
        }
        if gesture !== labelTap { host?.togglePageZoom(animated: true) }
    }
    @objc private func historyTap(_ gesture: UITapGestureRecognizer) {
        Task { if gesture === undoTap { await model?.performUndo() } else { await model?.performRedo() } }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let host, let model else { return }
        if model.pageNavigation == .vertical, host.flow?.page(at: gesture.location(in: host)) != model.page?.id {
            host.flow?.activateAtPoint(gesture.location(in: host)); return
        }
        let point = gesture.location(in: host.surface)
        if let note = model.lensNoteHit(at: point, tolerance: lensTolerance) {
            switch note.part {
            case .control: model.setLensNote(note.id, collapsed: true); model.finishLensSelection(); refresh(); return
            case .badge where model.tool != .objects: model.setLensNote(note.id, collapsed: false); model.finishLensSelection(); refresh(); return
            case .body where model.tool == .lens: model.lensNoteEditor = LensNoteEditTarget(id: note.id); model.finishLensSelection(); return
            default: break
            }
        }
        if model.tool == .lens {
            model.lensTap(at: point, anchor: host.surface.convert(CGRect(x: point.x - 70, y: point.y - 22, width: 140, height: 44), to: host),
                          tolerance: lensTolerance); return
        }
        if model.toggleChecklist(at: point) { return }
        if let tape = model.tapeHit(at: point), model.tool != .objects { model.toggleTape(tape); return }
        if model.tool == .text { model.beginTextEdit(at: point); host.textInput?.refresh() }
        else if model.tool == .audioLink { Task { await model.playAudio(at: point, tolerance: 18 / max(host.canvas.zoomScale, 0.1)) } }
        else if let id = hit(point) {
            if id == inkID { refresh(); return }
            if model.selectedObjectID == id, let text = model.page?.texts.first(where: { $0.id == id }), let target = text.pageLink {
                Task { await model.openPageLink(target) }; return
            }
            if model.selectedObjectID == id, let target = model.page?.shapes?.first(where: { $0.id == id })?.pageLink {
                Task { await model.openPageLink(target) }; return
            }
            if model.selectedObjectID == id, let text = model.page?.texts.first(where: { $0.id == id }),
               let url = RichText.link(at: point, text: text, pageHeight: model.page?.height ?? 1024),
               ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url); return }
            if model.multiSelection {
                if model.selectedIDs.contains(id) { model.selectedIDs.remove(id) } else { model.selectedIDs.insert(id) }
            } else { model.selectedObjectID = id }
        } else if !model.multiSelection { model.selectedObjectID = nil }
        refresh()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let host, let model, let page = model.page else { return }
        let point = gesture.location(in: host.surface)
        if gesture.state == .began { beginPan(at: point, page: page, host: host, model: model) }
        if gesture.state == .cancelled || gesture.state == .failed {
            if let before { model.page = before.page; if let data = before.drawing, let restored = try? PKDrawing(data: data) { model.canvas.drawing = restored } }
            endPreview(host: host)
            host.diagramPreview?.reset()
            model.movingObjects = false; marquee.path = nil; wordHighlight.path = nil
            snapEngine = nil; originalVisualBounds = nil; host.snapGuides?.show([])
            before = nil; original = [:]; originalDrawing = nil; movingLensNote = nil; refresh(); return
        }
        if model.tool == .lens && movingLensNote == nil { lensStroke(gesture, point: point, page: page, host: host, model: model); return }
        if model.selectRectangle || model.selectFreehand { selectArea(gesture, point: point, host: host, model: model); return }
        moveObjects(gesture, point: point, page: page, host: host, model: model)
    }

    private func beginPan(at point: CGPoint, page: PageSnapshot, host: CanvasHost, model: EditorViewModel) {
        model.cancelMaintenance()
        start = point; before = model.captureEdit(ink: model.selectionIncludesInk); original = [:]
        selectionTrace = [point]
        model.movingObjects = true
        originalDrawing = model.selectionIncludesInk ? model.canvas.drawing : nil
        movingLensNote = nil
        // With the Lens a note (or its 💡) is dragged to a new place instead of tracing a selection.
        if model.tool == .lens, let note = model.lensNoteHit(at: point, tolerance: lensTolerance), note.part != .control,
           !(page.lockedObjects ?? []).contains(note.id), let rect = objectRect(note.id, visual: false) {
            movingLensNote = note.id; model.selectedObjectID = note.id; original[note.id] = rect; resizing = false
        }
        if model.tool == .lens, movingLensNote == nil {
            model.lensPick = nil
            if !PageWordIndex.shared.isReady(page) { model.prepareLensWords() }
        }
        if !model.selectRectangle && !model.selectFreehand && model.tool != .lens {
            if let id = hit(point), id != inkID, !model.selectedIDs.contains(id) { model.selectedObjectID = id }
            model.selectedIDs = page.includingInternalConnectors(model.selectedIDs)
            for id in model.selectedIDs { original[id] = objectRect(id, visual: false) }
            if model.selectionIncludesInk { original[inkID] = model.selectedInkBounds }
            if original.count == 1, !model.selectionIncludesInk, let rect = original.values.first {
                resizing = hypot(point.x - rect.maxX, point.y - rect.maxY) <= 24 / max(host.canvas.zoomScale, 0.1)
                if let id = original.keys.first, page.shapes?.contains(where: { $0.id == id }) == true { resizing = false }
                if let id = original.keys.first, page.connectors?.contains(where: { $0.id == id }) == true { resizing = false }
                if let id = original.keys.first, page.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed == true { resizing = false }
            } else { resizing = false }
        }
        // One object moving: a picture of it follows the finger and the page changes once, on release.
        if original.count == 1, !model.selectionIncludesInk, let id = original.keys.first, previewable(id, page: page) {
            startPreview(id, page: page, host: host)
        }
        snapEngine = model.snapEngine(excluding: model.selectedIDs)
        if !original.isEmpty { host.diagramPreview?.start(page: page, moving: Set(original.keys)) }
        originalVisualBounds = original.keys.compactMap { $0 == inkID ? original[$0] : objectRect($0) }.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
    }

    /// The Lens stroke. With words on the page it highlights whole words as it goes:
    /// a flat stroke is a highlighter, a loop (or Area mode) a lasso. Without words
    /// (handwriting before its OCR, Immagine mode) the traced area is used as before.
    private func lensStroke(_ gesture: UIPanGestureRecognizer, point: CGPoint, page: PageSnapshot, host: CanvasHost, model: EditorViewModel) {
        selectionTrace.append(point)
        let mode = LensSettings.mode
        var picked: (words: [PageWord], indices: [Int])?
        if mode != .image {
            for words in PageWordIndex.shared.groups(for: page) {
                let indices = PageWords.pick(trace: selectionTrace, in: words, area: mode == .area)
                if !indices.isEmpty { picked = (words, indices); break }
            }
        }
        var transform = host.surface.transform; transform.tx = host.surface.frame.minX; transform.ty = host.surface.frame.minY
        let trace = UIBezierPath(); trace.move(to: start)
        for point in selectionTrace.dropFirst() { trace.addLine(to: point) }
        if mode == .area || mode == .image { trace.close() }
        // In Parole mode the highlight alone shows the selection, like a marker.
        let showTrace = picked == nil || mode != .text
        let display = UIBezierPath(cgPath: trace.cgPath); display.apply(transform)
        let marks = UIBezierPath()
        for rect in picked.map({ PageWords.lineRects($0.indices, in: $0.words) }) ?? [] {
            marks.append(UIBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3))
        }
        marks.apply(transform)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        marquee.path = showTrace ? display.cgPath : nil; wordHighlight.path = marks.cgPath
        CATransaction.commit()
        guard gesture.state == .ended else { return }
        model.movingObjects = false; marquee.path = nil; wordHighlight.path = nil; before = nil; originalDrawing = nil
        if let picked {
            let rects = PageWords.lineRects(picked.indices, in: picked.words)
            let area = rects.reduce(CGRect.null) { $0.union($1) }
            model.lensPicked(text: PageWords.text(picked.indices, in: picked.words), rects: rects, tap: false,
                             anchor: host.surface.convert(area, to: host))
            return
        }
        let samples = selectionTrace.map { StrokeSample(x: $0.x, y: $0.y) }
        if let area = LensGeometry.selection(trace: samples, pageWidth: page.width, pageHeight: page.height) {
            model.lensGesture(area: area, underline: mode == .text && LensGeometry.isUnderline(trace: samples), anchor: host.surface.convert(area, to: host))
        }
    }

    private func selectArea(_ gesture: UIPanGestureRecognizer, point: CGPoint, host: CanvasHost, model: EditorViewModel) {
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        let selection: UIBezierPath
        if model.selectFreehand {
            selectionTrace.append(point); selection = UIBezierPath(); selection.move(to: start)
            for point in selectionTrace.dropFirst() { selection.addLine(to: point) }; selection.close()
        } else { selection = UIBezierPath(rect: rect) }
        let display = UIBezierPath(cgPath: selection.cgPath)
        var transform = host.surface.transform; transform.tx = host.surface.frame.minX; transform.ty = host.surface.frame.minY
        display.apply(transform); marquee.path = display.cgPath
        guard gesture.state == .ended else { return }
        model.movingObjects = false
        let box = selection.bounds
        let ids = allIDs.filter { id in
            guard let frame = objectRect(id), frame.intersects(box) else { return false }
            if let page = model.page, let edge = page.connectors?.first(where: { $0.id == id }) {
                let objects = DiagramObjects.make(page)
                let polygon: [StrokeSample] = model.selectFreehand ? selectionTrace.map { .init(x: $0.x, y: $0.y) }
                    : [.init(x: rect.minX, y: rect.minY), .init(x: rect.maxX, y: rect.minY), .init(x: rect.maxX, y: rect.maxY), .init(x: rect.minX, y: rect.maxY)]
                if ConnectorGeometry.intersects(edge, objects: objects, selection: polygon) { return true }
                if let label = DiagramLabels.connector(edge, objects: objects, page: page), label.box.intersects(box) {
                    return !model.selectFreehand || selection.contains(CGPoint(x: label.box.midX, y: label.box.midY))
                }; return false
            }
            return !model.selectFreehand || selection.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        model.selectedIDs = model.multiSelection ? model.selectedIDs.union(ids) : Set(ids)
        let strokes = Set(model.canvas.drawing.strokes.indices.filter { index in
            let stroke = model.canvas.drawing.strokes[index]
            guard stroke.renderBounds.intersects(box) else { return false }
            return !model.selectFreehand || stroke.path.interpolatedPoints(by: .distance(8)).contains { selection.contains($0.location.applying(stroke.transform)) }
        })
        let previous = model.selectionIncludesInk ? (model.selectedStrokeIndices ?? Set(model.canvas.drawing.strokes.indices)) : []
        model.selectedStrokeIndices = model.multiSelection ? previous.union(strokes) : strokes
        model.selectionIncludesInk = !(model.selectedStrokeIndices?.isEmpty ?? true)
        model.selectRectangle = false; model.selectFreehand = false; marquee.path = nil; before = nil; originalDrawing = nil; refresh()
    }

    private func moveObjects(_ gesture: UIPanGestureRecognizer, point: CGPoint, page: PageSnapshot, host: CanvasHost, model: EditorViewModel) {
        var dx = Double(point.x - start.x), dy = Double(point.y - start.y)
        let group = original.values.reduce(nil as CGRect?, { $0?.union($1) ?? $1 })
        let keepRatio = resizing && (model.snapPreferences.keepProportions == true || original.keys.contains(where: { id in page.images.contains { $0.id == id } }))
        if keepRatio, let group { dy = dx * group.height / max(1, group.width) }
        if resizing, let group {
            var width = max(24, min(page.width - group.minX, group.width + dx))
            if keepRatio {
                let ratio = group.height / max(1, group.width)
                width = min(width, max(1, page.height - group.minY) / max(0.01, ratio))
                dy = width * ratio - group.height
            }
            dx = width - group.width
        }
        if !resizing, let group = original.values.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }) {
            let a = -Double(group.minX), b = page.width - Double(group.maxX)
            let c = -Double(group.minY), d = page.height - Double(group.maxY)
            dx = max(min(a, b), min(max(a, b), dx)); dy = max(min(c, d), min(max(c, d), dy))
        }
        if let engine = snapEngine, let group = resizing ? group : originalVisualBounds {
            let proposed = resizing
                ? SnapRect(x: group.minX, y: group.minY, width: max(1, group.width + dx), height: max(1, group.height + dy))
                : SnapRect(group.offsetBy(dx: dx, dy: dy))
            let snapped = engine.snap(proposed, zoom: host.canvas.zoomScale, preferences: model.snapPreferences,
                                      resizing: resizing, suspended: (gesture as? SnapPanGestureRecognizer)?.suspendsSnapping == true || gesture.modifierFlags.contains(.alternate))
            if resizing { dx = snapped.rect.width - group.width; dy = snapped.rect.height - group.height }
            else { dx = snapped.rect.x - group.minX; dy = snapped.rect.y - group.minY }
            var guides = snapped.guides
            if keepRatio {
                let ratio = group.height / max(1, group.width)
                if abs(snapped.rect.width - proposed.width) < 0.001, abs(snapped.rect.height - proposed.height) > 0.001 { dx = dy / ratio }
                dy = dx * ratio
                guides = guides.filter { abs($0.from.x - $0.to.x) < 0.01 ? abs($0.from.x - group.maxX - dx) < 0.1 : abs($0.from.y - group.maxY - dy) < 0.1 }
            }
            host.snapGuides?.show(guides)
        }
        host.diagramPreview?.updateMoving(frames: original, dx: dx, dy: dy, resizing: resizing, keepRatio: keepRatio)
        if dragPreview != nil, gesture.state != .ended {
            if resizing, let group {
                let sx = max(24, group.width + dx) / max(1, group.width)
                let sy = keepRatio ? sx : 1
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let tx = group.width * (sx - 1) / 2 * host.canvas.zoomScale
                let ty = group.height * (sy - 1) / 2 * host.canvas.zoomScale
                dragPreview?.setAffineTransform(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty))
                let box = CGRect(x: group.minX, y: group.minY, width: group.width * sx, height: group.height * sy)
                let display = host.surface.convert(box, to: host)
                outline.path = UIBezierPath(rect: display).cgPath
                handle.path = UIBezierPath(ovalIn: CGRect(x: display.maxX - 7, y: display.maxY - 7, width: 14, height: 14)).cgPath
                CATransaction.commit()
            } else { movePreview(dx: dx, dy: dy, host: host) }
            return
        }
        var changed = page
        for (id, rect) in original {
            let x = Double(rect.minX), y = Double(rect.minY), w = Double(rect.width), h = Double(rect.height)
            if let i = page.images.firstIndex(where: { $0.id == id }) {
                if resizing {
                    let ratio = h / max(1, w), available = min(max(1, page.width - x), max(1, page.height - y) / max(0.01, ratio))
                    let width = max(min(24, available), min(available, w + dx))
                    changed.images[i].width = width; changed.images[i].height = width * ratio
                } else { changed.images[i].x = x + dx; changed.images[i].y = y + dy }
            } else if let i = page.texts.firstIndex(where: { $0.id == id }) {
                if resizing {
                    changed.texts[i].width = max(24, min(page.width - x, w + dx))
                    if keepRatio, let source = before?.page.texts.first(where: { $0.id == id }) {
                        let scale = changed.texts[i].width / w
                        changed.texts[i] = RichText.scaled(source, by: scale)
                    }
                }
                else { changed.texts[i].x = x + dx; changed.texts[i].y = y + dy }
            } else if let i = page.shapes?.firstIndex(where: { $0.id == id }) {
                if resizing {
                    changed.shapes?[i].width = max(10, min(page.width - x, w + dx))
                    changed.shapes?[i].height = max(10, min(page.height - y, h + dy))
                } else { changed.shapes?[i].x = x + dx; changed.shapes?[i].y = y + dy }
            } else if let i = page.tapes?.firstIndex(where: { $0.id == id }) {
                if resizing {
                    changed.tapes?[i].width = max(10, min(page.width - x, w + dx))
                    changed.tapes?[i].height = max(10, min(page.height - y, h + dy))
                } else { changed.tapes?[i].x = x + dx; changed.tapes?[i].y = y + dy }
            } else if let i = page.connectors?.firstIndex(where: { $0.id == id }),
                      let source = before?.page.connectors?.first(where: { $0.id == id }) {
                var edge = source.transformed(dx: dx, dy: dy)
                if let target = edge.from.objectID, !model.selectedIDs.contains(target) { edge.from.objectID = nil }
                if let target = edge.to.objectID, !model.selectedIDs.contains(target) { edge.to.objectID = nil }
                changed.connectors?[i] = edge
            }
        }
        model.page = changed
        if dragPreview != nil {
            // Show the dropped object at once, before SwiftUI passes the page back.
            host.surface.page = changed
            endPreview(host: host)
        }
        if model.selectionIncludesInk, let drawing = originalDrawing {
            let transform = CGAffineTransform(translationX: dx, y: dy)
            model.canvas.drawing = PKDrawing(strokes: drawing.strokes.enumerated().map { index, stroke in
                guard model.selectedStrokeIndices == nil || model.selectedStrokeIndices?.contains(index) == true else { return stroke }
                return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(transform), mask: stroke.mask)
            })
        }
        refresh()
        if gesture.state == .ended {
            host.diagramPreview?.reset()
            model.movingObjects = false; model.drawingChanged()
            var label = resizing ? "Ridimensiona" : "Sposta selezione"
            if movingLensNote != nil { label = "Sposta nota della Lente" }
            model.recordEdit(before, label: label)
            before = nil; original = [:]; originalDrawing = nil
            snapEngine = nil; originalVisualBounds = nil; host.snapGuides?.show([])
            if movingLensNote != nil { movingLensNote = nil; model.selectedObjectID = nil; model.finishLensSelection(); refresh() }
        }
    }

    private func previewable(_ id: UUID, page: PageSnapshot) -> Bool {
        page.texts.contains { $0.id == id } || page.images.contains { $0.id == id } || (page.shapes ?? []).contains { $0.id == id }
    }

    private func startPreview(_ id: UUID, page: PageSnapshot, host: CanvasHost) {
        guard let visual = objectRect(id) else { return }
        let box = visual.insetBy(dx: -12, dy: -12)
        guard box.width > 0, box.height > 0 else { return }
        // Bound the actual bitmap, including Retina scale, to two million pixels.
        let budget = sqrt(2_000_000 / (box.width * box.height))
        let scale = min(budget, min(3, max(1, host.canvas.zoomScale * (host.window?.screen.scale ?? 2))))
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = false
        let package = host.surface.package
        let image = UIGraphicsImageRenderer(size: box.size, format: format).image { context in
            context.cgContext.translateBy(x: -box.minX, y: -box.minY)
            PageRenderer.drawSingle(id, page: page, package: package, in: context.cgContext)
        }
        let layer = CALayer()
        layer.contents = image.cgImage; layer.contentsScale = scale; layer.contentsGravity = .resize
        layer.frame = host.surface.convert(box, to: host)
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.25; layer.shadowRadius = 10; layer.shadowOffset = CGSize(width: 0, height: 6)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        host.layer.addSublayer(layer)
        CATransaction.commit()
        dragPreview = layer
        host.surface.hiddenObjectID = id
        host.foregroundObjects.update(host); host.lensNotes.update(host)
    }

    private func movePreview(dx: Double, dy: Double, host: CanvasHost) {
        let origin = host.surface.convert(CGPoint.zero, to: host)
        let moved = host.surface.convert(CGPoint(x: dx, y: dy), to: host)
        let shift = CGAffineTransform(translationX: moved.x - origin.x, y: moved.y - origin.y)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dragPreview?.setAffineTransform(shift); outline.setAffineTransform(shift); handle.setAffineTransform(shift)
        CATransaction.commit()
    }

    private func endPreview(host: CanvasHost) {
        guard let layer = dragPreview else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer(); outline.setAffineTransform(.identity); handle.setAffineTransform(.identity)
        CATransaction.commit()
        dragPreview = nil
        host.surface.hiddenObjectID = nil
        host.foregroundObjects.update(host); host.lensNotes.update(host)
    }
    /// Touch slack for note icons and controls, constant on screen at any zoom.
    private var lensTolerance: CGFloat { 10 / max(host?.canvas.zoomScale ?? 1, 0.1) }

    private var allIDs: [UUID] {
        guard let page = model?.page else { return [] }
        let locked = Set(page.lockedObjects ?? [])
        let above = Set(page.aboveInkObjects ?? []), tapes = Set((page.tapes ?? []).map(\.id)), ordered = page.orderedObjectIDs
        let visualOrder = ordered.filter { !above.contains($0) && !tapes.contains($0) } + ordered.filter { above.contains($0) && !tapes.contains($0) } + ordered.filter { tapes.contains($0) }
        return visualOrder.filter { !locked.contains($0) }
    }
    private func hit(_ point: CGPoint) -> UUID? {
        guard let host, let model else { return nil }
        let margin = 14 / max(host.canvas.zoomScale, 0.1)
        if model.selectedIDs.count == 1, let id = model.selectedObjectID,
           let rect = objectRect(id), CGRect(x: rect.maxX - margin, y: rect.maxY - margin, width: margin * 2, height: margin * 2).contains(point) { return id }
        if let id = allIDs.reversed().first(where: { id in
            if let page = model.page, let connector = page.connectors?.first(where: { $0.id == id }) {
                let objects = DiagramObjects.make(page)
                if let label = DiagramLabels.connector(connector, objects: objects, page: page), label.box.contains(point) { return true }
                return ConnectorGeometry.hit(.init(x: point.x, y: point.y), connector: connector, objects: objects, zoom: host.canvas.zoomScale)
            }
            if let shape = model.page?.shapes?.first(where: { $0.id == id }) {
                if let page = model.page, let label = DiagramLabels.shape(shape, page: page),
                   label.box.contains(point.applying(label.transform.inverted())) { return true }
                return ShapeGeometry.hit(.init(x: point.x, y: point.y), shape: shape, zoom: host.canvas.zoomScale)
            }
            return objectRect(id)?.contains(point) == true
        }) { return id }
        return model.selectionIncludesInk && model.selectedInkBounds.contains(point) ? inkID : nil
    }
    private func diagramLabelHit(_ point: CGPoint) -> UUID? {
        guard let model, let host, let page = model.page else { return nil }
        let tolerance = 8 / max(0.05, host.canvas.zoomScale)
        for id in allIDs.reversed() {
            guard objectRect(id)?.insetBy(dx: -tolerance, dy: -tolerance).contains(point) == true else { continue }
            if let shape = page.shapes?.first(where: { $0.id == id }) {
                if !shape.kind.isOpen, let outline = ShapeGeometry.polylines(ShapeGeometry.path(for: shape)).first,
                   ShapeGeometry.contains(.init(x: point.x, y: point.y), polygon: outline) { return id }
                if ShapeGeometry.hit(.init(x: point.x, y: point.y), shape: shape, zoom: host.canvas.zoomScale) { return id }
                if let label = DiagramLabels.shape(shape, page: page), label.box.contains(point.applying(label.transform.inverted())) { return id }
            } else if let edge = page.connectors?.first(where: { $0.id == id }) {
                let objects = DiagramObjects.make(page)
                if ConnectorGeometry.hit(.init(x: point.x, y: point.y), connector: edge, objects: objects, zoom: host.canvas.zoomScale) { return id }
                if let label = DiagramLabels.connector(edge, objects: objects, page: page), label.box.contains(point) { return id }
            }
        }
        return nil
    }
    private func objectRect(_ id: UUID, visual: Bool = true) -> CGRect? {
        guard let page = model?.page else { return nil }
        if let connector = page.connectors?.first(where: { $0.id == id }) {
            let objects = DiagramObjects.make(page)
            var box = ConnectorGeometry.bounds(connector, objects: objects).cgRect
            if let label = DiagramLabels.connector(connector, objects: objects, page: page) { box = box.union(label.box) }
            return box
        }
        if let tape = page.tapes?.first(where: { $0.id == id }) { return CGRect(x: tape.x, y: tape.y, width: tape.width, height: tape.height) }
        if let image = page.images.first(where: { $0.id == id }) {
            let box = CGRect(x: image.x, y: image.y, width: image.width, height: image.height)
            let angle = image.rotation ?? 0
            // Quarter-turn images already store their visual width/height.
            guard visual, abs(angle.truncatingRemainder(dividingBy: 180)) != 90 else { return box }
            let transform = CGAffineTransform(translationX: -box.midX, y: -box.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle * .pi / 180))
                .concatenating(CGAffineTransform(translationX: box.midX, y: box.midY))
            return box.applying(transform)
        }
        if let shape = page.shapes?.first(where: { $0.id == id }) {
            let box = CGRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height)
            if visual {
                let frame = ShapeGeometry.bounds(shape)
                var result = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                if let label = DiagramLabels.shape(shape, page: page) { result = result.union(label.box.applying(label.transform)) }
                return result
            }
            return box
        }
        if let text = page.texts.first(where: { $0.id == id }) {
            let box = RichText.bounds(text, pageHeight: page.height)
            return visual ? box.applying(RichText.rotation(text, pageHeight: page.height)) : box
        }
        return nil
    }
}

@MainActor
extension CanvasInteraction: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let host, let model, model.hasLease, model.tool == .objects, !model.selectionPageDragMode,
              !model.interactionBusy, !model.navigating, !model.loading,
              let id = hit(host.surface.convert(location, from: host)), id != inkID else { return nil }
        if !model.selectedIDs.contains(id) { model.selectedObjectID = id }; refresh()
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let model = self?.model else { return nil }
            let copy = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { _ in model.copySelection() }
            let duplicate = UIAction(title: "Duplica", image: UIImage(systemName: "plus.square.on.square")) { _ in model.duplicateSelectedObject() }
            let edit = UIAction(title: "Modifica", image: UIImage(systemName: "slider.horizontal.3")) { _ in
                if let text = model.page?.texts.first(where: { model.selectedIDs.contains($0.id) }) {
                    model.chooseTool(.text); model.beginTextEdit(at: CGPoint(x: text.x + 2, y: text.y + 2))
                } else { model.objectEditorRequest += 1 }
            }
            let front = UIAction(title: "Porta davanti", image: UIImage(systemName: "square.3.layers.3d.top.filled")) { _ in model.arrangeSelection(front: true) }
            let back = UIAction(title: "Porta dietro", image: UIImage(systemName: "square.3.layers.3d.bottom.filled")) { _ in model.arrangeSelection(front: false) }
            let lock = UIAction(title: "Blocca", image: UIImage(systemName: "lock")) { _ in model.lockSelection() }
            let ai = UIAction(title: "Chiedi alla Lente AI", image: UIImage(systemName: "sparkles")) { _ in model.lensAskAboutSelection() }
            let remove = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in model.deleteSelectedObject() }
            var lens: [UIMenuElement] = []
            if let note = model.page?.texts.first(where: { $0.id == id })?.lensNote {
                let collapsed = note.isCollapsed
                lens.append(UIAction(title: collapsed ? "Apri nota" : "Riduci a 💡", image: UIImage(systemName: "note.text")) { _ in model.setLensNote(id, collapsed: !collapsed) })
                lens.append(UIAction(title: "Modifica nota della Lente", image: UIImage(systemName: "square.and.pencil")) { _ in model.lensNoteEditor = LensNoteEditTarget(id: id) })
                if note.source != nil {
                    lens.append(UIAction(title: "Mostra il testo di origine", image: UIImage(systemName: "text.viewfinder")) { _ in Task { await model.focusLensNote(id, source: true) } })
                }
            }
            var items: [UIMenuElement] = [edit, copy, duplicate, ai, UIMenu(title: "Livelli", children: [front, back, lock]), remove]
            if model.page?.shapes?.contains(where: { $0.id == id }) == true || model.page?.connectors?.contains(where: { $0.id == id }) == true {
                items.insert(UIAction(title: "Modifica etichetta", image: UIImage(systemName: "textformat")) { _ in model.editDiagramLabel(id) }, at: 1)
            }
            if let target = model.page?.shapes?.first(where: { $0.id == id })?.pageLink {
                items.insert(UIAction(title: "Apri la fonte", image: UIImage(systemName: "arrow.up.forward.app")) { _ in Task { await model.openPageLink(target) } }, at: 1)
            }
            if model.selectedConnector != nil {
                let routes = ConnectorRouting.allCases.map { routing in UIAction(title: routing.title) { _ in model.setConnectorRouting(routing) } }
                items.insert(UIMenu(title: "Tracciato", children: routes), at: 1)
                items.insert(UIAction(title: "Stile del connettore", image: UIImage(systemName: "paintbrush.pointed")) { _ in model.connectorStyleRequest += 1 }, at: 1)
            }
            if model.arrangementCount >= 2 {
                let actions = SelectionArrangement.allCases.map { action in
                    UIAction(title: action.title, attributes: model.arrangementCount < action.minimumCount ? .disabled : []) { _ in model.arrangeSelection(action) }
                }
                items.insert(UIMenu(title: "Allinea e distribuisci", children: actions), at: 1)
            }
            if model.page?.images.contains(where: { $0.id == id }) == true {
                items.insert(UIAction(title: "Raddrizza immagine", image: UIImage(systemName: "viewfinder")) { _ in
                    model.selectedObjectID = id; model.imageStraightenRequest += 1
                }, at: 1)
            }
            if !lens.isEmpty { items.insert(UIMenu(title: "", options: .displayInline, children: lens), at: 0) }
            return UIMenu(children: items)
        }
    }
}
