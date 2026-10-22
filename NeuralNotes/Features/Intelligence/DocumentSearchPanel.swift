import SwiftUI
import NeuralNotesCore

@MainActor
struct DocumentSearchPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [IndexedChunk] = []
    @State private var attachments: [Attachment] = []
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var semantic = false
    @State private var indexing: String?
    @State private var searchGeneration = UUID()

    var body: some View {
        NavigationStack {
            List {
                if let indexing { Section { HStack { ProgressView(); Text(indexing).font(.caption) } } }
                Section {
                    Toggle("Cerca per significato con il modello locale", isOn: $semantic)
                    if semantic { Text("Usa gli embedding italiani disponibili nel sistema. La disponibilità dipende dai modelli installati.").font(.caption) }
                }
                if !query.isEmpty {
                    Section("Risultati nel documento") {
                        ForEach(Array(results.enumerated()), id: \.offset) { row in
                            Button { Task { await navigate(row.element.reference) } } label: {
                                VStack(alignment: .leading) {
                                    SearchResultText(text: row.element.text, query: query)
                                    Text(location(row.element.reference)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if results.isEmpty { Text("Nessun risultato. Per gli appunti a mano esegui prima OCR.").foregroundStyle(.secondary) }
                    }
                }
                Section("Allegati originali") {
                    ForEach(attachments) { attachment in
                        Button(attachment.originalName, systemImage: "paperclip") {
                            Task {
                                do { shareURL = try await model.workspace.url(attachment.file); sharing = true }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Ricerca e allegati")
            .searchable(text: $query, prompt: "Testo, OCR, PDF e trascrizioni")
            .task(id: query + (semantic ? ":semantic" : ":text")) { await search() }
            .task { await prepare() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(isPresented: $sharing) { if let shareURL { ShareDocument(url: shareURL) } }
        }
    }

    /// Opens with the words picked with the Lens, and reads once the text layer of the
    /// PDF pages that were not read at import, so numbers, names and terms are found.
    private func prepare() async {
        if let pending = model.pendingSearchQuery { model.pendingSearchQuery = nil; query = pending }
        guard await model.flush() else { return }
        var batch: [(pageID: UUID, revision: Int, text: String)] = []
        defer { indexing = nil }
        do {
            let missing = try await model.workspace.pagesNeedingPDFText()
            for (number, page) in missing.enumerated() {
                try Task.checkCancellation()
                indexing = "Leggo il testo del PDF: pagina \(number + 1) di \(missing.count)…"
                let text = try await DocumentServices.pdfText(page: page, workspace: model.workspace)
                // A successful empty probe is remembered, while scans remain eligible for OCR.
                batch.append((page.id, page.revision, text.trimmingCharacters(in: .whitespacesAndNewlines)))
                if batch.count >= 50 { _ = try await model.workspace.storePDFText(batch); batch = [] }
            }
            if !batch.isEmpty { _ = try await model.workspace.storePDFText(batch) }
            if !query.isEmpty { await search() }
        } catch is CancellationError {
            // Completed batches persist; the next opening resumes the rest.
        } catch {
            self.error = "Lettura PDF non completata: \(error.localizedDescription). Riapri la ricerca per riprendere."
        }
    }

    private func search() async {
        let input = query, useSemantic = semantic
        let generation = UUID(); searchGeneration = generation
        error = nil
        do {
            if !input.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
            guard await model.flush() else { return }
            attachments = try await model.workspace.catalog().attachments
            let id = try await model.workspace.manifest().documentID
            let chunks = try await FileDocumentIndexingService(workspace: model.workspace, id: id).index(documentID: id)
            try Task.checkCancellation()
            let selected: [IndexedChunk]
            if input.isEmpty { selected = [] }
            else if useSemantic {
                selected = try await SemanticRetrievalService(embeddings: AppleEmbeddingService()).retrieve(question: input, from: chunks, limit: 12)
            } else { selected = Array(chunks.lazy.filter { $0.text.localizedStandardContains(input) }.prefix(200)) }
            try Task.checkCancellation()
            guard generation == searchGeneration, input == query, useSemantic == semantic else { return }; results = selected
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func location(_ source: SourceReference) -> String {
        if let id = source.pageID, let index = model.pages.firstIndex(where: { $0.id == id }) { return "Pagina \(index + 1)" }
        if let seconds = source.seconds { return "Audio · \(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))" }
        return "Documento"
    }

    private func navigate(_ source: SourceReference) async {
        if let id = source.pageID, let page = model.pages.first(where: { $0.id == id }) {
            await model.select(page)
            if model.page?.id == id { model.searchFocus = SearchFocusRequest(pageID: id, query: String(query.prefix(200))); dismiss() }
        }
        else if let id = source.audioSessionID, let session = model.audio?.sessions.first(where: { $0.id == id }) {
            await model.audio?.play(session, at: source.seconds ?? 0)
        }
    }
}

@MainActor
struct AreaRecognitionPanel: View {
    let image: UIImage
    var workspace: DocumentWorkspace? = nil
    var pageID: UUID? = nil
    let onRecognized: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: CGPoint?
    @State private var selection = CGRect.zero
    @State private var displaySize = CGSize.zero
    @State private var busy = false
    @State private var text = ""
    @State private var error: String?
    @State private var outline: String?

    var body: some View {
        NavigationStack {
            VStack {
                Text("Trascina un rettangolo sull’area da riconoscere.").font(.callout)
                GeometryReader { geometry in
                    let fit = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        Rectangle().stroke(.teal, lineWidth: 2).background(.teal.opacity(0.12))
                            .frame(width: selection.width, height: selection.height)
                            .offset(x: selection.minX, y: selection.minY)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        displaySize = size
                        if start == nil { start = value.startLocation }
                        let a = start ?? value.startLocation
                        selection = CGRect(x: min(a.x, value.location.x), y: min(a.y, value.location.y),
                            width: abs(a.x - value.location.x), height: abs(a.y - value.location.y))
                            .intersection(CGRect(origin: .zero, size: size))
                    }.onEnded { _ in start = nil })
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if !text.isEmpty { ScrollView { Text(text).textSelection(.enabled) }.frame(maxHeight: 150) }
                Button("Riconosci area") { Task { await recognize() } }.disabled(busy || selection.width < 8 || selection.height < 8)
                if !text.isEmpty, workspace != nil {
                    Button("Crea schema dell’area", systemImage: "list.bullet.indent") { Task { await makeOutline() } }.disabled(busy)
                }
                if let outline { ScrollView { Text(outline).textSelection(.enabled) }.frame(maxHeight: 180) }
            }.padding()
            .navigationTitle("OCR di una selezione")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func recognize() async {
        guard let cg = image.cgImage, displaySize.width > 0 else { return }
        busy = true; defer { busy = false }
        let scale = Double(cg.width) / displaySize.width
        let rect = CGRect(x: selection.minX * scale, y: selection.minY * scale,
                          width: selection.width * scale, height: selection.height * scale)
        guard let cropped = cg.cropping(to: rect), let data = UIImage(cgImage: cropped).pngData() else { return }
        do {
            text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
            onRecognized(text)
        } catch { self.error = error.localizedDescription }
    }

    private func makeOutline() async {
        guard let workspace else { return }
        busy = true; defer { busy = false }
        do {
            let manifest = try await workspace.manifest()
            let reference = SourceReference(documentID: manifest.documentID, pageID: pageID)
            let artifact = try await ExtractiveStudyProvider().generate(AIRequest(task: .outline, question: "",
                sources: [IndexedChunk(text: text, reference: reference)]))
            try await workspace.saveArtifact(artifact); outline = artifact.text
        } catch { self.error = error.localizedDescription }
    }
}
