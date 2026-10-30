import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum SelectiveInkEraser {
    /// Clip existing vector masks directly. Rebuilding the visible outline of
    /// every stroke at 2-point intervals was the main-thread bottleneck.
    static func erase(_ drawing: PKDrawing, samples: [StrokeSample], width: Double, wholeStroke: Bool) -> (PKDrawing, Bool) {
        guard let first = samples.first else { return (drawing, false) }
        let trace = CGMutablePath(); trace.move(to: CGPoint(x: first.x, y: first.y))
        for point in samples.dropFirst() { trace.addLine(to: CGPoint(x: point.x, y: point.y)) }
        let area: CGPath
        if samples.allSatisfy({ hypot($0.x - first.x, $0.y - first.y) < 0.1 }) {
            area = CGPath(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width), transform: nil)
        } else { area = trace.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1) }
        var result: [PKStroke] = [], changed = false
        for stroke in drawing.strokes {
            guard stroke.ink.inkType == .marker, stroke.renderBounds.intersects(area.boundingBoxOfPath) else { result.append(stroke); continue }
            if wholeStroke {
                if InkScratchEraser.erase(PKDrawing(strokes: [stroke]), in: area, wholeStroke: true).erased { changed = true }
                else { result.append(stroke) }
                continue
            }
            let t = stroke.transform
            guard abs(t.a * t.d - t.b * t.c) > 0.000001 else { result.append(stroke); continue }
            var inverse = t.inverted()
            guard let cut = area.copy(using: &inverse) else { result.append(stroke); continue }
            let base = stroke.mask.map { $0.cgPath.normalized(using: $0.usesEvenOddFillRule ? .evenOdd : .winding) }
                ?? CGPath(rect: stroke.renderBounds.applying(inverse).insetBy(dx: -2, dy: -2), transform: nil)
            guard !base.intersection(cut, using: .winding).isEmpty else { result.append(stroke); continue }
            let remaining = base.subtracting(cut, using: .winding); changed = true
            if !remaining.isEmpty { result.append(PKStroke(ink: stroke.ink, path: stroke.path, transform: t, mask: UIBezierPath(cgPath: remaining), randomSeed: stroke.randomSeed)) }
        }
        return (changed ? PKDrawing(strokes: result) : drawing, changed)
    }
}

@MainActor
final class MarkerEraseSession {
    private weak var model: EditorViewModel?
    private let before: EditorContentState?
    private let original: PKDrawing
    private let pageID: UUID?
    private let width: Double
    private let whole: Bool
    private var queued: [StrokeSample] = []
    private var tail: StrokeSample?
    private var frame: Task<Void, Never>?
    private var changed = false
    init(model: EditorViewModel) {
        self.model = model; before = model.captureEdit(ink: true); original = model.canvas.drawing; pageID = model.page?.id
        width = model.writingOptions.eraserWidth; whole = model.writingOptions.eraser == .stroke
        model.eraserCompositionToken = UUID()
    }
    func append(_ samples: [StrokeSample]) {
        queued += samples
        guard frame == nil else { return }
        frame = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            self?.process(); self?.frame = nil
        }
    }
    private func process() {
        guard let model, model.page?.id == pageID, !queued.isEmpty else { return }
        let samples = tail.map { [$0] + queued } ?? queued; tail = queued.last; queued = []
        let (drawing, erased) = SelectiveInkEraser.erase(model.canvas.drawing, samples: samples, width: width, wholeStroke: whole)
        if erased { changed = true; model.canvas.drawing = drawing }
    }
    func finish(cancelled: Bool) {
        frame?.cancel(); frame = nil
        guard let model else { return }
        defer { model.eraserCompositionToken = nil }
        guard model.page?.id == pageID else { return }
        if cancelled { model.installNativeInk(original); return }
        process()
        if changed {
            model.installNativeInk(model.canvas.drawing)
            model.recordEdit(before, label: "Cancella evidenziatore"); model.drawingChanged(preservingRecognizedWords: true)
        }
        if model.writingOptions.returnToPen { model.chooseTool(.pen) }
    }
}
