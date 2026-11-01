import UIKit
import PencilKit
import NeuralNotesCore

/// The Lens and the marker use the same sources, priority and word selection.
/// In word mode the preview commits vector word rectangles, never raw ink.
@MainActor
final class MarkerWordSession {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private let before: PKDrawing
    private let pageID: UUID
    private let wordMode: Bool
    private var groups: [[PageWord]]
    private var ready: Bool
    private var trace: [CGPoint] = []
    private let preview: LiveMarkerPreview
    private let color: UIColor
    private let width: Double
    private let page: PageSnapshot
    private struct WordRect: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    }
    private let existingHighlights: Set<WordRect>
    private var lastWordRects: [CGRect]?
    var selectsWords: Bool { wordMode }
    init?(host: CanvasHost, model: EditorViewModel) {
        guard let page = model.page, model.markerCustomInput else { return nil }
        self.host = host; self.model = model; pageID = page.id; before = model.canvas.drawing
        wordMode = model.wordHighlightEnabled
        groups = wordMode ? PageWordIndex.shared.groups(for: page) : []
        ready = PageWordIndex.shared.isReady(page)
        self.page = page; color = PaperInk.color(model.ink); width = model.markerWidth
        let selectedColor = InkColor(model.ink)
        existingHighlights = Set((page.pdfMarkups ?? []).filter {
            $0.wordHighlight == true && ($0.color ?? .yellow) == selectedColor && ($0.opacity ?? 0.25) == 0.25
        }.map { WordRect(CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) })
        preview = LiveMarkerPreview(host: host, page: page, baseline: before, color: color)
        model.strokeBegan(); model.drawingShape = true
    }
    private func refreshWords() {
        guard wordMode, !ready, let page = model?.page, page.id == pageID, PageWordIndex.shared.isReady(page) else { return }
        groups = PageWordIndex.shared.groups(for: page); ready = true
    }
    func move(_ samples: [CGPoint]) {
        guard host != nil else { return }; trace.append(contentsOf: samples)
        if trace.count > 2000 { trace = trace.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trace.count - 1 }.map(\.element) }
        refreshWords()
        let path = UIBezierPath()
        if wordMode, let selected = PageWords.selection(trace: trace, groups: groups) {
            // Use the exact committed word rectangles and skip already-colored words.
            let pageBox = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            let rects = selected.indices.map { selected.words[$0].rect.insetBy(dx: -1.5, dy: -1.5).intersection(pageBox) }
                .filter { !$0.isNull && !$0.isEmpty && !existingHighlights.contains(WordRect($0)) }
            guard rects != lastWordRects else { return }
            lastWordRects = rects
            for rect in rects { path.append(UIBezierPath(rect: rect)) }
            preview.update(path: path.cgPath)
        } else if !wordMode {
            for (i, p) in trace.enumerated() { if i == 0 { path.move(to: p) } else { path.addLine(to: p) } }
            preview.update(path: path.cgPath.copy(strokingWithWidth: CGFloat(width), lineCap: .round, lineJoin: .round, miterLimit: 10))
        } else { lastWordRects = nil; preview.update(path: path.cgPath) }
    }

    func finish(cancelled: Bool) {
        defer {
            if let host {
                host.synchronizePage(); host.surface.layer.displayIfNeeded(); host.paperDetail.layer.displayIfNeeded(); host.emptyInkCover.layer.displayIfNeeded()
                host.foregroundObjects.layer.displayIfNeeded(); host.markerReadability.layer.displayIfNeeded()
            }
            preview.removeFromSuperview()
        }
        guard let model, model.page?.id == pageID else { return }
        if wordMode {
            refreshWords()
            let selected = PageWords.selection(trace: trace, groups: groups)
            model.cancelGuidedInk(before)
            guard !cancelled else { return }
            if let selected { model.highlightWords(selected) }
            else {
                model.status = model.page.map { PageWordIndex.shared.isPreparing($0) } == true
                    ? "Lettura delle parole in corso: ripassa quando sono pronte"
                    : "Nessuna parola selezionata. Per disegnare scegli Tratto libero"
                model.prepareMarkerWords()
            }
            return
        }
        model.drawingShape = false
        guard !cancelled, trace.count > 1 else { model.cancelGuidedInk(before); return }
        let strokeWidth = CGFloat(self.width)
        let samples = trace.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: .init(width: strokeWidth, height: strokeWidth),
                opacity: 0.25, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.marker, color: color), path: PKStrokePath(controlPoints: samples, creationDate: Date()))
        model.installNativeInk(PKDrawing(strokes: before.strokes + [stroke]))
        model.strokeEnded(); model.finishInkGesture()
    }
}
