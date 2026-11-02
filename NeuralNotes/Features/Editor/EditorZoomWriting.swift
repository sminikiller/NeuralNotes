import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func toggleZoomWriting() {
        if zoomWritingOpen { closeZoomWriting(); return }
        guard hasLease, !loading, !navigating, !interactionBusy, audio?.replayInk != true else { return }
        if tool != .pen && tool != .marker && tool != .eraser { chooseTool(.pen) }
        finishInkGesture(); endTextEdit(); zoomWritingOpen = true; configureTool()
    }
    func closeZoomWriting() {
        guard zoomWritingOpen || zoomWritingController != nil else { return }
        zoomWritingController?.finishAndClose()
        zoomWritingOpen = false
        if hasLease { configureTool() }
    }
}
