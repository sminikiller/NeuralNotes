import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
private enum EditorClipboard {
    static var page: PageSnapshot?
    static var drawing: Data?
    static var package: URL?
}

@MainActor
extension EditorViewModel {
    func selectAll() {
        guard let page else { return }
        selectedIDs = Set(page.texts.map(\.id) + page.images.map(\.id) + (page.shapes ?? []).map(\.id))
        selectionIncludesInk = !canvas.drawing.strokes.isEmpty
        selectedStrokeIndices = nil
    }
    func rotateSelectedImage() {
        guard selectedIDs.count == 1, let id = selectedObjectID else { return }
        mutatePage("Ruota immagine") { page in
            if let i = page.images.firstIndex(where: { $0.id == id }) {
                page.images[i].rotation = ((page.images[i].rotation ?? 0) + 90).truncatingRemainder(dividingBy: 360)
                let width = page.images[i].width; page.images[i].width = page.images[i].height; page.images[i].height = width
                if page.images[i].width > page.width - 32 {
                    let factor = max(24, page.width - 32) / page.images[i].width
                    page.images[i].width *= factor; page.images[i].height *= factor
                }
                page.images[i].x = min(page.images[i].x, max(0, page.width - page.images[i].width))
            }
        }
    }
    func copySelection() {
        guard var copy = page else { return }
        copy.texts.removeAll { !selectedIDs.contains($0.id) }; copy.images.removeAll { !selectedIDs.contains($0.id) }
        copy.shapes = copy.shapes?.filter { selectedIDs.contains($0.id) }
        let drawing: PKDrawing
        if let selectedStrokeIndices { drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().filter { selectedStrokeIndices.contains($0.offset) }.map(\.element)) }
        else { drawing = canvas.drawing }
        let bytes = selectionIncludesInk ? drawing.dataRepresentation() : nil
        guard (bytes?.count ?? 0) <= 32 * 1024 * 1024 else { error = "Selezione troppo grande per gli appunti interni. Copia una parte più piccola."; return }
        EditorClipboard.page = copy; EditorClipboard.drawing = bytes; EditorClipboard.package = workspace.package
        status = "Selezione copiata"
    }
    func pasteSelection() async {
        guard hasLease, !navigating, !hasActiveStroke else { return }
        guard let copy = EditorClipboard.page, let source = EditorClipboard.package else { return }
        navigating = true; defer { navigating = false }
        let before = captureEdit(ink: EditorClipboard.drawing != nil)
        do {
            // Decode before mutating page objects: a corrupt clipboard must not
            // leave a partially pasted page that was never marked dirty.
            let copiedDrawing = try EditorClipboard.drawing.map { try PKDrawing(data: $0) }
            var images = copy.images
            if source != workspace.package {
                for i in images.indices {
                    let url = try NativeArchive.fileURL(images[i].file, in: source)
                    let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url, options: .mappedIfSafe) }.value
                    images[i].file = try await workspace.storeImage(data)
                }
            }
            var ids = Set<UUID>()
            for var text in copy.texts { text.id = UUID(); text.x += 20; text.y += 20; page?.texts.append(text); ids.insert(text.id) }
            for var image in images { image.id = UUID(); image.x += 20; image.y += 20; page?.images.append(image); ids.insert(image.id) }
            for var shape in copy.shapes ?? [] {
                shape.id = UUID(); shape.x += 20; shape.y += 20
                page?.shapes = (page?.shapes ?? []) + [shape]; ids.insert(shape.id)
            }
            if let copied = copiedDrawing {
                let strokes = copied.strokes.enumerated().map { index, stroke in
                    PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: Array(stroke.path),
                        creationDate: Date().addingTimeInterval(Double(index) * 0.001)),
                        transform: stroke.transform.concatenating(CGAffineTransform(translationX: 20, y: 20)), mask: stroke.mask)
                }
                canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + strokes)
            }
            selectedIDs = ids; selectionIncludesInk = false; selectedStrokeIndices = nil
            recordEdit(before, label: "Incolla selezione"); drawingChanged()
        } catch { self.error = error.localizedDescription }
    }
}
