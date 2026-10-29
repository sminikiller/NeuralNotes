import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var shapePreferences: ShapePreferences { currentWorkspace.shapes ?? ShapePreferences() }
    var recognitionMode: ShapeRecognitionMode { shapePreferences.mode ?? (currentWorkspace.holdShapes ? .hold : .off) }
    func editShapePreferences(_ action: (inout ShapePreferences) -> Void) {
        editWorkspace { workspace in
            var value = workspace.shapes ?? ShapePreferences(); action(&value)
            if value.isValid {
                workspace.shapes = value
                if let mode = value.mode { workspace.holdShapes = mode != .off }
            }
        }
    }
    func chooseShape(_ kind: ShapeKind) {
        guard !hasActiveStroke else { return }
        shapeKind = kind; tool = .shape; restoreToolPalette(); configureTool()
    }
    func shapeForDrag(_ kind: ShapeKind, from a: StrokeSample, to b: StrokeSample) -> ShapeElement? {
        let snapped = ShapeSnapping.drag(kind: kind, start: a, end: b)
        guard var shape = ShapeElement.dragged(kind: kind, from: a, to: snapped.end, color: InkColor(ink), lineWidth: thickness) else { return nil }
        shape.sides = kind == .star ? max(4, shapePreferences.sides ?? 5) : (kind == .polygon ? (shapePreferences.sides ?? 6) : nil)
        shape.innerRatio = kind == .star ? (shapePreferences.innerRatio ?? 0.5) : nil
        var style = shapePreferences.style ?? .standard
        style.color = nil; style.width = nil
        shape = style.applying(to: shape)
        return shape
    }
    func addDraggedShape(_ kind: ShapeKind, from a: StrokeSample, to b: StrokeSample) {
        guard var shape = shapeForDrag(kind, from: a, to: b) else { return }
        if let (session, seconds) = audio?.recordingAnchor {
            shape.audioAnchor = StrokeAnchor(signature: "shape:\(shape.id)", audioSessionID: session, seconds: seconds)
        }
        mutatePage("Traccia \(kind.title)") { $0.shapes = ($0.shapes ?? []) + [shape] }
        selectedObjectID = shape.id; rememberPalette()
    }
    var selectedShapes: [ShapeElement] { (page?.shapes ?? []).filter { selectedIDs.contains($0.id) } }
    func applyShapeStyle(_ style: NeuralNotesCore.ShapeStyle) {
        guard style.isValid else { return }
        let ids = selectedIDs
        mutatePage("Stile forme") { page in
            page.shapes = page.shapes?.map { ids.contains($0.id) ? style.applying(to: $0) : $0 }
        }
    }
    func applyShapeStyleAndParameters(_ style: NeuralNotesCore.ShapeStyle, template: ShapeElement?) {
        guard style.isValid else { return }
        let ids = selectedIDs
        mutatePage("Stile e parametri forme") { page in
            page.shapes = page.shapes?.map { source in
                guard ids.contains(source.id) else { return source }
                var value = style.applying(to: source)
                if let template, source.kind == template.kind {
                    value.sides = template.sides; value.innerRatio = template.innerRatio
                    value.arcSweep = template.arcSweep
                }
                return value
            }
        }
    }
    func updateShapeParameters(_ template: ShapeElement) {
        let ids = selectedIDs
        mutatePage("Parametri forma") { page in
            page.shapes = page.shapes?.map { source in
                guard ids.contains(source.id), source.kind == template.kind else { return source }
                var value = source; value.sides = template.sides; value.innerRatio = template.innerRatio
                return value
            }
        }
    }
    func applyHeldShapeIfNeeded() -> Bool {
        defer { pendingHeldShape = nil; pendingShapeRecognition = nil; pendingAutomaticRecognition = false }
        guard recognitionMode != .off, tool == .pen || tool == .marker,
              let held = pendingHeldShape, held.page == page?.id, let bytes = editBeforeGesture?.drawing,
              let previous = try? PKDrawing(data: bytes), canvas.drawing.strokes.count == previous.strokes.count + 1,
              let original = canvas.drawing.strokes.last else { return false }
        if shapePreferences.output == .ink || tool == .marker {
            let oldSignature = EditorInkSignatures.make(canvas.drawing).last
            let corrected = PreciseStrokeGeometry.stroke(kind: held.kind, points: held.samples, original: original)
            canvas.drawing = PKDrawing(strokes: previous.strokes + [corrected])
            if let oldSignature, let signature = EditorInkSignatures.make(canvas.drawing).last {
                if var anchors = page?.anchors {
                    for i in anchors.indices where anchors[i].signature == oldSignature { anchors[i].signature = signature }
                    page?.anchors = anchors
                }
            }
            return true
        }
        let recognized = pendingShapeRecognition ?? ShapeRecognizer.recognize(held.samples)
        guard var shape = recognized?.shape ?? PreciseStrokeGeometry.shape(kind: held.kind, points: held.samples) else { return false }
        shape = (shapePreferences.style ?? .standard).applying(to: shape)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        original.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        shape.red = Double(red); shape.green = Double(green); shape.blue = Double(blue)
        shape.lineWidth = min(200, max(0.1, Double(original.path.first?.size.width ?? CGFloat(thickness)))); shape.strokeOpacity = Double(alpha)
        let originalSignature = EditorInkSignatures.make(canvas.drawing).last
        guard var current = page else { return false }
        if let signature = originalSignature {
            shape.audioAnchor = current.anchors.first(where: { $0.signature == signature })
            current.anchors.removeAll { $0.signature == signature }
        }
        current.shapes = (current.shapes ?? []) + [shape]
        page = current
        canvas.drawing = previous
        return true
    }
    func showRecognitionNotice(_ title: String) {
        recognitionNoticeTask?.cancel(); recognitionNotice = "Corretto in \(title)"
        recognitionNoticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.recognitionNotice = nil
        }
    }
}
