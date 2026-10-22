import SwiftUI
import NeuralNotesCore

@MainActor
struct GlobalSearchPanel: View {
    let library: LibraryViewModel
    let open: (Notebook, SourceReference, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [Hit] = []
    @State private var busy = false
    @State private var error: String?
    @State private var kind: SearchContentKind?
    @State private var onlyFolder = false
    @State private var indexer = LibraryOCRIndexer()
    @AppStorage("search.automaticOCR") private var automaticOCR = true
    @AppStorage("search.spotlight") private var spotlight = false
    private struct Hit: Identifiable {
        let id: Int
        let notebook: Notebook
        let chunk: IndexedChunk
    }
    var body: some View {
        NavigationStack {
            List {
                Toggle("Indicizza la grafia nelle pause di scrittura", isOn: $automaticOCR)
                Toggle("Quaderni in Spotlight", isOn: $spotlight)
                Text("Spotlight usa soltanto titoli e tag dei quaderni. Il testo degli appunti resta nella ricerca interna.").font(.caption).foregroundStyle(.secondary)
                if !SpotlightIndexer.shared.message.isEmpty { Text(SpotlightIndexer.shared.message).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Testo PDF e grafia dei quaderni") {
                    Button(indexer.running ? "Sospendi indicizzazione" : "Indicizza i quaderni esistenti", systemImage: indexer.running ? "pause.circle" : "text.viewfinder") { if indexer.running { indexer.stop() } else { indexer.start(library) } }
                    if !indexer.status.isEmpty { Text(indexer.status).font(.caption).foregroundStyle(.secondary) }
                    Text("Una pagina per volta: testo digitale dei PDF, poi OCR quando serve. Riprende dalle revisioni completate; i quaderni aperti vengono saltati.").font(.caption)
                }
                Picker("Contenuto", selection: $kind) {
                    Text("Tutto").tag(nil as SearchContentKind?)
                    ForEach(SearchContentKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                if library.currentFolderID != nil { Toggle("Solo questa cartella e sottocartelle", isOn: $onlyFolder) }
                if busy { ProgressView("Ricerca nei quaderni…") }
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(hits) { hit in
                    Button {
                        dismiss(); open(hit.notebook, hit.chunk.reference, query)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hit.notebook.title).font(.headline)
                            SearchResultText(text: hit.chunk.text, query: query)
                            if let time = hit.chunk.reference.seconds { Text("Audio · \(TranscriptText.clock(time))").font(.caption) }
                            else { Text("Pagina del quaderno").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !busy && hits.isEmpty { Text(query.count < 2 ? "Cerca almeno due caratteri in testi, PDF, OCR e trascrizioni di tutti i quaderni." : "Nessun risultato.").foregroundStyle(.secondary) }
            }.navigationTitle("Cerca negli appunti")
                .searchable(text: $query, prompt: "Tutti i quaderni")
                .task(id: spotlight) { await SpotlightIndexer.shared.update(library) }
                .task(id: query + "|" + (kind?.rawValue ?? "all") + "|\(onlyFolder)") { await search() }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
                .onDisappear { indexer.stop() }
        }
    }
    private func search() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { hits = []; return }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        busy = true; defer { busy = false }; error = nil
        var results: [Hit] = []
        let books = onlyFolder && library.currentFolderID != nil ? library.notebooksInFolderTree(library.currentFolderID!) : library.notebooks
        for book in books {
            do {
                try Task.checkCancellation()
                let chunks = try await library.workspace(book).indexedChunks()
                for chunk in chunks where (kind == nil || chunk.kind == kind) && chunk.text.localizedStandardContains(query) {
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
