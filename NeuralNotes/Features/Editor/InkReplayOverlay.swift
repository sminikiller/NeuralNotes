import UIKit
import PencilKit
import NeuralNotesCore

/// A disposable display layer. Never writes a filtered PKDrawing back to the
/// document, so stopping playback restores all ink without undo or disk writes.
@MainActor
final class InkReplayOverlay: UIImageView {
    private var key = ""
    private var previousVisible: [Int] = []
    private var drawing = PKDrawing()
    private var signatures: [String] = []
    private var active = false
    private weak var host: CanvasHost?
    private var previousMode: AudioReplayMode?
    private var previousHot: [Int] = []
    private var previousHidden = Set<UUID>()
    private var previousPDFVersion = -1
    init() {
        super.init(frame: .zero); isHidden = true; isUserInteractionEnabled = false; contentMode = .scaleToFill
        NotificationCenter.default.addObserver(self, selector: #selector(nnReplayPDFReady(_:)), name: PDFRasterCache.didRender, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func nnReplayPDFReady(_ note: Notification) {
        guard let host, let page = host.model?.page, active, PDFRasterCache.affects(note, page: page, package: host.surface.package) else { return }
        update(host)
    }
    required init?(coder: NSCoder) { nil }
    func resetForPageChange(_ host: CanvasHost) {
        host.surface.replayHiddenObjectIDs = []
        host.canvas.layer.opacity = 1
        active = false; image = nil; isHidden = true; key = ""
        drawing = PKDrawing(); signatures = []; previousVisible = []
    }
    func update(_ host: CanvasHost) {
        self.host = host
        guard let model = host.model, let page = model.page, let audio = model.audio,
              audio.replayInk, let sessionID = audio.playingSessionID else {
            if !host.surface.replayHiddenObjectIDs.isEmpty {
                host.surface.replayHiddenObjectIDs = []; host.paperDetail.update(from: host); host.foregroundObjects.update(host)
            }
            if active {
                host.canvas.layer.opacity = 1; active = false; isHidden = true; image = nil; key = ""
                host.model?.configureTool()
            }; return
        }
        let hiddenShapes = Set((page.shapes ?? []).compactMap { shape -> UUID? in
            guard let anchor = shape.audioAnchor, anchor.audioSessionID == sessionID, anchor.seconds > audio.playback else { return nil }
            return shape.id
        })
        let hiddenEdges = Set((page.connectors ?? []).compactMap { edge -> UUID? in
            let future = edge.audioAnchor.map { $0.audioSessionID == sessionID && $0.seconds > audio.playback } ?? false
            let hiddenStart = edge.from.objectID.map { hiddenShapes.contains($0) } ?? false
            let hiddenEnd = edge.to.objectID.map { hiddenShapes.contains($0) } ?? false
            return future || hiddenStart || hiddenEnd ? edge.id : nil
        })
        let hiddenObjects: Set<UUID> = audio.replayMode == .showAll ? [] : hiddenShapes.union(hiddenEdges)
        if hiddenObjects != host.surface.replayHiddenObjectIDs {
            host.surface.replayHiddenObjectIDs = hiddenObjects; host.paperDetail.update(from: host); host.foregroundObjects.update(host)
        }
        let generation = "\(page.id)|\(page.revision)|\(host.canvas.drawing.strokes.count)|\(sessionID)|\(model.inkDisplayGeneration)"
        if key != generation {
            key = generation; drawing = host.canvas.drawing
            signatures = EditorInkSignatures.make(drawing)
            previousVisible = [-1]
        }
        let visible = audio.replayMode == .showAll ? Array(drawing.strokes.indices) : AudioReplay.visible(signatures: signatures, anchors: page.anchors, sessionID: sessionID, seconds: audio.playback)
        let hot = audio.replayMode == .showAll ? AudioReplay.current(signatures: signatures, anchors: page.anchors, sessionID: sessionID, seconds: audio.playback) : []
        let pdfVersion = PDFRasterCache.shared.version(page: page, package: host.surface.package)
        if visible != previousVisible || hot != previousHot || previousMode != audio.replayMode || previousHidden != hiddenObjects || previousPDFVersion != pdfVersion {
            let filtered = PKDrawing(strokes: visible.map { drawing.strokes[$0] })
            let box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            let format = UIGraphicsImageRendererFormat(); format.scale = min(2, 2048 / max(page.width, page.height))
            image = UIGraphicsImageRenderer(bounds: box, format: format).image { renderer in
                PageRenderer.draw(page, package: host.surface.package, in: renderer.cgContext, hidingObjectIDs: hiddenObjects, pdfMode: .interactive)
                LegibleInkRenderer.draw(filtered, in: renderer.cgContext, bounds: box, scale: format.scale)
                if !hot.isEmpty {
                    let emphasized = PKDrawing(strokes: hot.map { index in
                        let stroke = drawing.strokes[index]
                        return PKStroke(ink: PKInk(.pen, color: .systemTeal), path: stroke.path, transform: stroke.transform, mask: stroke.mask)
                    })
                    renderer.cgContext.saveGState(); renderer.cgContext.setAlpha(0.65)
                    LegibleInkRenderer.draw(emphasized, in: renderer.cgContext, bounds: box, scale: format.scale)
                    renderer.cgContext.restoreGState()
                }
            }
            previousVisible = visible; previousHot = hot; previousHidden = hiddenObjects
            previousMode = audio.replayMode; previousPDFVersion = pdfVersion
        }
        frame = host.surface.frame; isHidden = false; active = true
        host.canvas.layer.opacity = 0; host.canvas.drawingGestureRecognizer.isEnabled = false
    }
}
