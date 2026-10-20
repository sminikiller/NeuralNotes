import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func turnPage(_ delta: Int) async {
        guard !interactionBusy, hasLease, let current = page, let index = pages.firstIndex(where: { $0.id == current.id }), !navigating, !loading else { return }
        let next = index + delta
        if pages.indices.contains(next) { await select(pages[next]) }
    }
    func advanceOrAddPage() async {
        guard !interactionBusy, hasLease, let current = page, let index = pages.firstIndex(where: { $0.id == current.id }), !navigating else { return }
        if pages.indices.contains(index + 1) { await select(pages[index + 1]) }
        else { await addPage() }
    }

    func eraseScratchIfNeeded() -> Bool {
        let enabled = currentWorkspace.scratchErase
        guard enabled, tool == .pen,
              let before = editBeforeGesture?.drawing, let previous = try? PKDrawing(data: before),
              canvas.drawing.strokes.count == previous.strokes.count + 1,
              let scratch = canvas.drawing.strokes.last, let page else { return false }
        let samples = scratch.path.interpolatedPoints(by: .distance(3)).prefix(1500).map { point -> StrokeSample in
            let location = point.location.applying(scratch.transform)
            return StrokeSample(x: Double(location.x), y: Double(location.y))
        }
        guard ScratchGesture.matches(samples) else { return false }
        let area = InkScratchEraser.coverage(of: scratch)
        var texts = page.texts, textChanged = false
        for index in texts.indices {
            let corrected = TextScratchEraser.eraseWords(texts[index], in: area, pageHeight: page.height)
            if corrected != texts[index].text { texts[index].text = corrected; textChanged = true }
        }
        let erased = InkScratchEraser.erase(previous, in: area)
        guard textChanged || erased.erased else { return false }
        self.page?.texts = texts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        canvas.drawing = erased.drawing
        selectedObjectID = nil
        return true
    }
}
