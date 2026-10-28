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
    init() { super.init(frame: .zero); isHidden = true; isUserInteractionEnabled = false; contentMode = .scaleToFill }
    required init?(coder: NSCoder) { nil }
    func resetForPageChange(_ host: CanvasHost) {
        host.surface.replayHiddenObjectIDs = []
        host.canvas.layer.opacity = 1
        active = false; image = nil; isHidden = true; key = ""
        drawing = PKDrawing(); signatures = []; previousVisible = []
    }
    func update(_ host: CanvasHost) {
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
        if hiddenShapes != host.surface.replayHiddenObjectIDs {
            host.surface.replayHiddenObjectIDs = hiddenShapes; host.paperDetail.update(from: host); host.foregroundObjects.update(host)
        }
        let generation = "\(page.id)|\(page.revision)|\(host.canvas.drawing.strokes.count)|\(sessionID)"
        if key != generation {
            key = generation; drawing = host.canvas.drawing
            signatures = EditorInkSignatures.make(drawing)
            previousVisible = [-1]
        }
        let visible = AudioReplay.visible(signatures: signatures, anchors: page.anchors, sessionID: sessionID, seconds: audio.playback)
        if visible != previousVisible {
            let filtered = PKDrawing(strokes: visible.map { drawing.strokes[$0] })
            image = PaperInk.image(filtered, from: CGRect(x: 0, y: 0, width: page.width, height: page.height), scale: min(2, 2048 / max(page.width, page.height)))
            previousVisible = visible
        }
        frame = host.surface.frame; isHidden = false; active = true
        host.canvas.layer.opacity = 0; host.canvas.drawingGestureRecognizer.isEnabled = false
    }
}
