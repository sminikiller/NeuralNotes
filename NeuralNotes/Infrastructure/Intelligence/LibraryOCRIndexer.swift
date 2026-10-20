import Foundation
import Observation
import PencilKit
import NeuralNotesCore

@MainActor @Observable
final class LibraryOCRIndexer {
    private(set) var running = false
    private(set) var status = ""
    private(set) var failures = 0
    @ObservationIgnored private var job: Task<Void, Never>?
    func start(_ library: LibraryViewModel) {
        guard !running else { return }; running = true; failures = 0
        let books = library.notebooks
        job = Task {
            defer { running = false; job = nil }
            var count = 0
            for book in books {
                do {
                    try Task.checkCancellation()
                    let workspace = try library.workspace(book), ids = try await workspace.manifest().pageIDs
                    for (index, id) in ids.enumerated() {
                        try Task.checkCancellation(); status = "\(book.title) · pagina \(index + 1) di \(ids.count)"
                        if try await process(id, workspace: workspace) { count += 1 }
                        await Task.yield()
                    }
                } catch is CancellationError { status = "Indicizzazione sospesa. Le pagine completate restano ricercabili."; return }
                catch { failures += 1 }
            }
            status = "Indicizzate \(count) pagine · \(failures) quaderni da riprovare. I quaderni aperti vengono lasciati all’editor."
        }
    }
    func stop() { job?.cancel() }
    private func process(_ id: UUID, workspace: DocumentWorkspace) async throws -> Bool {
        // Share the same exclusive reservation as a cloud replacement, so a
        // package cannot be swapped while its image is being recognized.
        guard EditorLeases.shared.reserveCloud(workspace.documentID) else { return false }
        defer { EditorLeases.shared.releaseCloud(workspace.documentID) }
        let page = try await workspace.pageSnapshot(id)
        guard await workspace.needsAutomaticOCR(pageID: id, revision: page.revision) else { return false }
        guard page.drawingFile != nil || !page.images.isEmpty || (page.pdfFile != nil && page.recognizedText.isEmpty) else { return false }
        let bytes = try await workspace.drawing(page)
        let drawing = try bytes.map { try PKDrawing(data: $0) } ?? PKDrawing()
        var visual = page; visual.texts = []; visual.tapes = []; visual.shapes = []
        let image = DocumentServices.image(page: visual, drawing: drawing, workspace: workspace, maxDimension: 1600)
        guard let data = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
        let text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
        try Task.checkCancellation()
        return try await workspace.storeAutomaticOCR(pageID: id, revision: page.revision, text: text)
    }
}
