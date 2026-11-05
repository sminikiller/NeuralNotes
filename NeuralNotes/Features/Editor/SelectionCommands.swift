import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
private enum EditorClipboard {
    static var current: SelectionSnapshot?
    static var changeCount: Int?
}

@MainActor
extension EditorViewModel {
    func selectAll() {
        guard let page else { return }
        selectedIDs = Set(page.objectIDs).subtracting(page.lockedObjects ?? [])
        selectionIncludesInk = canEditActiveLayer && !canvas.drawing.strokes.isEmpty
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
    @discardableResult
    func copySelection(maximumBytes: Int = 32 * 1024 * 1024) -> Bool {
        guard var copy = page, !selectedIDs.isEmpty || selectionIncludesInk else { return false }
        copy = copy.selectingObjects(selectedIDs, objects: DiagramObjects.make(copy))
        let drawing: PKDrawing
        if let selectedStrokeIndices { drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().filter { selectedStrokeIndices.contains($0.offset) }.map(\.element)) }
        else { drawing = canvas.drawing }
        let bytes = selectionIncludesInk ? drawing.dataRepresentation() : nil
        do { EditorClipboard.current = try SelectionSnapshot(page: copy, drawing: bytes, source: workspace.package, maximumBytes: maximumBytes) }
        catch { self.error = "Selezione non copiata: controlla che i media esistano e scegli una parte più piccola (limite \(max(0, maximumBytes) / (1024 * 1024)) MB). Gli originali restano nel foglio."; return false }
        EditorClipboard.changeCount = UIPasteboard.general.changeCount
        status = "Selezione copiata"
        return true
    }
    func cutSelection(maximumBytes: Int = 32 * 1024 * 1024) {
        if copySelection(maximumBytes: maximumBytes) { deleteSelectedObject() }
    }
    func pasteSelection(plainText: Bool = false) async {
        finishInkGesture(); endTextEdit()
        guard hasLease, canEditActiveLayer, !loading, !navigating, !hasActiveStroke, page != nil else { return }
        // Keep this snapshot alive across awaits even if another window copies
        // a different selection while the media are being pasted.
        if EditorClipboard.current == nil || EditorClipboard.changeCount != UIPasteboard.general.changeCount {
            pasteSystemText(plain: plainText); return
        }
        guard let clipboard = EditorClipboard.current else { return }
        defer { withExtendedLifetime(clipboard) { } }
        var copy = clipboard.page; let source = clipboard.package
        if plainText { for i in copy.texts.indices { copy.texts[i].rtf = nil; copy.texts[i].fontSize = 18 } }
        copy.renewObjectIDs()
        navigating = true; defer { navigating = false }
        let before = captureEdit(ink: clipboard.drawing != nil)
        do {
            // Decode before mutating page objects: a corrupt clipboard must not
            // leave a partially pasted page that was never marked dirty.
            let copiedDrawing = try clipboard.drawing.map { try PKDrawing(data: $0) }
            var images = copy.images
            if source != workspace.package {
                for i in images.indices {
                    let url = try NativeArchive.fileURL(images[i].file, in: source)
                    let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url, options: .mappedIfSafe) }.value
                    images[i].file = try await workspace.storeImage(data)
                }
            }
            var ids = Set<UUID>()
            for var text in copy.texts { text.x += 20; text.y += 20; page?.texts.append(text); ids.insert(text.id) }
            for var image in images { image.x += 20; image.y += 20; page?.images.append(image); ids.insert(image.id) }
            for var shape in copy.shapes ?? [] {
                shape.x += 20; shape.y += 20
                var shapes = page?.shapes ?? []; shapes.append(shape); page?.shapes = shapes; ids.insert(shape.id)
            }
            for var tape in copy.tapes ?? [] {
                tape.x += 20; tape.y += 20
                var tapes = page?.tapes ?? []; tapes.append(tape); page?.tapes = tapes; ids.insert(tape.id)
            }
            let edges = (copy.connectors ?? []).map { $0.transformed(dx: 20, dy: 20) }
            if !edges.isEmpty {
                var values = page?.connectors ?? []; values.append(contentsOf: edges); page?.connectors = values
                ids.formUnion(edges.map(\.id))
            }
            if let copied = copiedDrawing {
                let strokes = copied.strokes.enumerated().map { index, stroke in
                    PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: Array(stroke.path),
                        creationDate: Date().addingTimeInterval(Double(index) * 0.001)),
                        transform: stroke.transform.concatenating(CGAffineTransform(translationX: 20, y: 20)), mask: stroke.mask, randomSeed: stroke.randomSeed)
                }
                canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + strokes)
            }
            if let current = page {
                page?.objectOrder = current.orderedObjectIDs.filter { !ids.contains($0) } + copy.orderedObjectIDs
                page?.aboveInkObjects = Array(Set(current.aboveInkObjects ?? []).union(copy.aboveInkObjects ?? []))
            }
            selectedIDs = ids; selectionIncludesInk = false; selectedStrokeIndices = nil
            recordEdit(before, label: "Incolla selezione"); drawingChanged()
        } catch { self.error = error.localizedDescription }
    }
    private func pasteSystemText(plain: Bool) {
        guard let value = TextPasteboard.read(plain: plain, attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black]),
              !value.string.isEmpty, let current = page else { return }
        var text = TextElement(text: value.string)
        text.rtf = RichText.data(value)
        text.width = min(480, current.width - 48); text.x = 24; text.y = 48
        if let host = pagePresenter as? CanvasHost {
            let point = host.surface.convert(CGPoint(x: host.bounds.midX, y: host.bounds.midY), from: host)
            text.x = min(max(0, point.x - text.width / 2), current.width - text.width)
            text.y = min(max(0, point.y), current.height - 40)
        }
        mutatePage(plain ? "Incolla testo semplice" : "Incolla testo formattato") { $0.texts.append(text) }
        selectedObjectID = text.id
    }

}
