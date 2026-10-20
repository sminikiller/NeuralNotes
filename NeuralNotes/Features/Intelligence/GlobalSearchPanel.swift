import SwiftUI
import NeuralNotesCore

@MainActor
struct GlobalSearchPanel: View {
    let library: LibraryViewModel
    let open: (Notebook, SourceReference) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [Hit] = []
    @State private var busy = false
    @State private var error: String?
    @AppStorage("search.automaticOCR") private var automaticOCR = true
    private struct Hit: Identifiable {
        let id: Int
        let notebook: Notebook
        let chunk: IndexedChunk
    }
    var body: some View {
        NavigationStack {
            List {
                Toggle("Indicizza la grafia nelle pause di scrittura", isOn: $automaticOCR)
                if busy { ProgressView("Ricerca nei quaderni…") }
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(hits) { hit in
                    Button {
                        dismiss(); open(hit.notebook, hit.chunk.reference)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hit.notebook.title).font(.headline)
                            Text(hit.chunk.text).lineLimit(4).foregroundStyle(.primary)
                            if let time = hit.chunk.reference.seconds { Text("Audio · \(TranscriptText.clock(time))").font(.caption) }
                            else { Text("Pagina del quaderno").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !busy && hits.isEmpty { Text(query.count < 2 ? "Cerca almeno due caratteri in testi, PDF, OCR e trascrizioni di tutti i quaderni." : "Nessun risultato.").foregroundStyle(.secondary) }
            }.navigationTitle("Cerca negli appunti")
                .searchable(text: $query, prompt: "Tutti i quaderni")
                .task(id: query) { await search() }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
    private func search() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { hits = []; return }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        busy = true; defer { busy = false }; error = nil
        var results: [Hit] = []
        for book in library.notebooks {
            do {
                try Task.checkCancellation()
                let chunks = try await library.workspace(book).indexedChunks()
                for chunk in chunks where chunk.text.localizedStandardContains(query) {
                    results.append(Hit(id: results.count, notebook: book, chunk: chunk))
                    if results.count >= 200 { break }
                }
                if results.count >= 200 { break }
            } catch is CancellationError { return }
            catch { self.error = "Alcuni quaderni non sono leggibili: \(book.title). Puoi verificarli in Recupero quaderni." }
        }
        guard !Task.isCancelled else { return }; hits = results
    }
}
