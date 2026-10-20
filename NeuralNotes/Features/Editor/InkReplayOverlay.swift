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
    func update(_ host: CanvasHost) {
        guard let model = host.model, let page = model.page, let audio = model.audio,
              audio.replayInk, let sessionID = audio.playingSessionID else {
            if active {
                host.canvas.layer.opacity = 1; active = false; isHidden = true; image = nil; key = ""
                host.model?.configureTool()
            }; return
        }
        let generation = "\(page.id)|\(page.revision)|\(host.canvas.drawing.strokes.count)|\(sessionID)"
        if key != generation {
            key = generation; drawing = host.canvas.drawing
            var occurrences: [String: Int] = [:]
            signatures = drawing.strokes.map { stroke in
                let base = String(stroke.path.creationDate.timeIntervalSince1970)
                let count = occurrences[base, default: 0]; occurrences[base] = count + 1; return "\(base):\(count)"
            }
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
