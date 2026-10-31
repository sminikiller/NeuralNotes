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
    private let preview = CAShapeLayer()
    var selectsWords: Bool { wordMode }
    init?(host: CanvasHost, model: EditorViewModel) {
        guard let page = model.page, model.markerCustomInput else { return nil }
        self.host = host; self.model = model; pageID = page.id; before = model.canvas.drawing
        wordMode = model.wordHighlightEnabled
        groups = wordMode ? PageWordIndex.shared.groups(for: page) : []
        ready = PageWordIndex.shared.isReady(page)
        preview.fillColor = PaperInk.color(model.ink).withAlphaComponent(0.25).cgColor
        preview.strokeColor = nil
        if !wordMode {
            preview.fillColor = nil; preview.strokeColor = PaperInk.color(model.ink).withAlphaComponent(0.4).cgColor
            preview.lineWidth = CGFloat(model.markerWidth) * host.canvas.zoomScale; preview.lineCap = .round; preview.lineJoin = .round
        }
        host.layer.addSublayer(preview)
        model.strokeBegan(); model.drawingShape = true
    }
    private func refreshWords() {
        guard wordMode, !ready, let page = model?.page, page.id == pageID, PageWordIndex.shared.isReady(page) else { return }
        groups = PageWordIndex.shared.groups(for: page); ready = true
    }
    func move(_ samples: [CGPoint]) {
        guard let host else { return }; trace.append(contentsOf: samples)
        if trace.count > 2000 { trace = trace.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trace.count - 1 }.map(\.element) }
        refreshWords()
        let path = UIBezierPath()
        if wordMode, let selected = PageWords.selection(trace: trace, groups: groups) {
            for rect in PageWords.lineRects(selected.indices, in: selected.words) {
                let box = host.surface.convert(rect.insetBy(dx: -1.5, dy: -1.5), to: host)
                path.append(UIBezierPath(roundedRect: box, cornerRadius: 3 * host.canvas.zoomScale))
            }
        } else if !wordMode {
            for (i, p) in trace.enumerated() {
                let at = host.surface.convert(p, to: host)
                if i == 0 { path.move(to: at) } else { path.addLine(to: at) }
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true); preview.path = path.cgPath; CATransaction.commit()
    }
    func finish(cancelled: Bool) {
        preview.removeFromSuperlayer()
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
        let width = CGFloat(model.markerWidth)
        let samples = trace.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: .init(width: width, height: width),
                opacity: 0.4, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.marker, color: PaperInk.color(model.ink)), path: PKStrokePath(controlPoints: samples, creationDate: Date()))
        model.installNativeInk(PKDrawing(strokes: before.strokes + [stroke]))
        model.strokeEnded(); model.finishInkGesture()
    }
}
