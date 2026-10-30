import UIKit
import PencilKit
import NeuralNotesCore

/// Digital PDF words share the Lens geometry. Only display changes while the
/// pointer moves; all selected words form one history/audio transaction at lift.
@MainActor
final class MarkerWordSession {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private let words: [PageWord]
    private let before: PKDrawing
    private let pageID: UUID
    private var trace: [CGPoint] = []
    private var picked: [Int] = []
    private let preview = CAShapeLayer()
    init?(host: CanvasHost, model: EditorViewModel) {
        guard let page = model.page, model.markerWordsActive else { return nil }
        self.host = host; self.model = model; words = PageWordIndex.shared.pdfWords(page)
        pageID = page.id; before = model.canvas.drawing
        preview.fillColor = PaperInk.color(model.ink).withAlphaComponent(0.18).cgColor
        preview.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor; preview.lineWidth = 1
        host.layer.addSublayer(preview)
        model.strokeBegan(); model.drawingShape = true
    }
    func move(_ samples: [CGPoint]) {
        guard let host else { return }; trace.append(contentsOf: samples)
        if trace.count > 2000 { trace = trace.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trace.count - 1 }.map(\.element) }
        picked = PageWords.pick(trace: trace, in: words, area: false)
        let path = UIBezierPath()
        for i in picked { path.append(UIBezierPath(rect: host.surface.convert(words[i].rect, to: host))) }
        CATransaction.begin(); CATransaction.setDisableActions(true); preview.path = path.cgPath; CATransaction.commit()
    }
    func finish(cancelled: Bool) {
        preview.removeFromSuperlayer()
        guard let model, model.page?.id == pageID else { return }
        model.drawingShape = false
        guard !cancelled else { model.cancelGuidedInk(before); return }
        var strokes: [PKStroke] = []
        for r in PageWords.lineRects(picked, in: words) {
            let vertical = r.height > r.width * 1.4
            let width = max(1, min(80, vertical ? r.width : r.height))
            let inset = min(width / 2, (vertical ? r.height : r.width) / 2)
            let points = vertical
                ? [CGPoint(x: r.midX, y: r.minY + inset), CGPoint(x: r.midX, y: r.maxY - inset)]
                : [CGPoint(x: r.minX + inset, y: r.midY), CGPoint(x: r.maxX - inset, y: r.midY)]
            strokes.append(stroke(points, width: width, model: model, mask: r))
        }
        if strokes.isEmpty, trace.count > 1 { strokes = [stroke(trace, width: CGFloat(model.markerWidth), model: model)] }
        guard !strokes.isEmpty else { model.cancelGuidedInk(before); return }
        model.installNativeInk(PKDrawing(strokes: before.strokes + strokes))
        model.strokeEnded(); model.finishInkGesture()
    }
    private func stroke(_ points: [CGPoint], width: CGFloat, model: EditorViewModel, mask: CGRect? = nil) -> PKStroke {
        let samples = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: .init(width: width, height: width),
                opacity: 0.4, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.marker, color: PaperInk.color(model.ink)), path: PKStrokePath(controlPoints: samples, creationDate: Date()),
            mask: mask.map { UIBezierPath(rect: $0) })
    }
}
