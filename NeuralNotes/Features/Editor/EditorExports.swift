import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func exportPageImage(jpeg: Bool = false, selection: Bool = false) throws -> URL {
        guard let page else { throw WorkspaceFailure.emptyDocument }
        let image = selection ? try selectionImage() : DocumentServices.image(page: page, drawing: canvas.drawing, workspace: workspace, maxDimension: 4096)
        guard let bytes = jpeg ? image.jpegData(compressionQuality: 0.94) : image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-\(UUID()).\(jpeg ? "jpg" : "png")")
        try bytes.write(to: file, options: .atomic); return file
    }
    func selectionImage() throws -> UIImage {
        guard let page else { throw WorkspaceFailure.emptyDocument }
        let box = selectionBounds.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        guard !box.isNull, box.width > 0, box.height > 0 else { throw WorkspaceFailure.emptyDocument }
        let image = DocumentServices.image(page: page, drawing: canvas.drawing, workspace: workspace, maxDimension: 2048)
        let pixels = CGRect(x: box.minX * image.scale, y: box.minY * image.scale, width: box.width * image.scale, height: box.height * image.scale).integral
        guard let cropped = image.cgImage?.cropping(to: pixels) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: cropped)
    }
    func copySelectionImage() { do { UIPasteboard.general.image = try selectionImage(); status = "Area copiata come immagine" } catch { self.error = error.localizedDescription } }
    func exportNotebookText(markdown: Bool = true, highlightsOnly: Bool = false) async throws -> URL {
        let pages = try await workspace.pages(), catalog = try await workspace.catalog()
        var blocks: [String] = []
        for (index, page) in pages.enumerated() {
            var lines: [String] = []
            if !highlightsOnly {
                lines += page.texts.map(\.text); lines += (page.shapes ?? []).compactMap(\.label); lines += (page.connectors ?? []).compactMap(\.label)
                if !page.recognizedText.isEmpty { lines.append(page.recognizedText) }
            }
            lines += (page.pdfMarkups ?? []).map { "\($0.kind == .highlight ? "Evidenziato" : "Sottolineato"): \($0.text)" }
            if !lines.isEmpty { blocks.append("\(markdown ? "## " : "")Pagina \(index + 1)\n\n" + lines.joined(separator: "\n\n")) }
        }
        if !highlightsOnly {
            for session in catalog.sessions {
                let minutes = TranscriptText.minutes(session.readableTranscript)
                if !minutes.isEmpty { blocks.append("\(markdown ? "## " : "")\(session.title)\n\n" + minutes.map { "[\(TranscriptText.clock($0.start))] \($0.text)" }.joined(separator: "\n\n")) }
            }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-\(UUID()).\(markdown ? "md" : "txt")")
        try blocks.joined(separator: "\n\n").write(to: file, atomically: true, encoding: .utf8); return file
    }
    func convertSelectionToText() async {
        guard hasLease, !interactionBusy, !navigating, !loading, let page else { return }
        let bounds = selectionBounds; guard !bounds.isNull else { return }
        navigating = true; defer { navigating = false }
        let before = captureEdit(ink: selectionIncludesInk), selected = selectedIDs, inkIndices = selectedStrokeIndices
        do {
            let image = try selectionImage()
            guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
            let text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Nessun testo leggibile nella selezione."; return }
            guard self.page?.id == page.id else { throw WorkspaceFailure.staleRevision }
            self.page?.texts.removeAll { selected.contains($0.id) }; self.page?.images.removeAll { selected.contains($0.id) }
            self.page?.shapes?.removeAll { selected.contains($0.id) }; self.page?.tapes?.removeAll { selected.contains($0.id) }
            if selectionIncludesInk {
                canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().filter { inkIndices?.contains($0.offset) == false }.map(\.element))
            }
            var element = TextElement(text: text); element.x = bounds.minX; element.y = bounds.minY
            element.width = max(40, min(bounds.width, page.width - bounds.minX)); element.fontSize = 20
            self.page?.texts.append(element); self.page?.pruneObjectReferences()
            recordEdit(before, label: "Converti selezione in testo"); selectedObjectID = element.id; drawingChanged()
        } catch { self.error = error.localizedDescription }
    }
}
