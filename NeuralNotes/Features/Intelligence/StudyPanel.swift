import SwiftUI
import NeuralNotesCore

@MainActor
struct StudyPanel: View {
    let model: EditorViewModel
    let notebook: Notebook
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var glossary = false
    @State private var task = AITask.summarize
    @State private var question = ""
    @State private var includeFolder = false
    @State private var result: AIArtifact?
    @State private var error: String?
    @State private var busy = false
    @State private var job: Task<Void, Never>?
    @State private var semantic = false
    @State private var history: [AIArtifact] = []
    @State private var contextNotice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fonti") {
                    Text("L’AI usa il testo digitato, il testo dei PDF, l’OCR e le trascrizioni già salvate. Esegui prima OCR sulle pagine scritte a mano.")
                        .font(.callout)
                    Text("Invia al massimo 40 estratti entro 80.000 caratteri. Senza una domanda, li distribuisce dall’inizio alla fine; un documento grande viene campionato, non letto integralmente.").font(.caption).foregroundStyle(.secondary)
                    if notebook.folderID != nil { Toggle("Includi quaderni della stessa cartella", isOn: $includeFolder) }
                    Picker("Attività", selection: $task) {
                        ForEach(AITask.allCases, id: \.self) { value in Text(value.title).tag(value) }
                    }
                    TextField("Domanda o istruzioni", text: $question, axis: .vertical).lineLimit(3...6)
                    Button("Motore: \(configuration.engine.title)", systemImage: "slider.horizontal.3") { configuring = true }
                    Button("Glossario del quaderno", systemImage: "character.book.closed") { glossary = true }
                    Toggle("Seleziona le fonti per significato (modello locale)", isOn: $semantic)
                }
                if configuration.engine == .offline {
                    Section { Text("La sintesi locale seleziona frasi dalle fonti. Funziona offline e non usa un modello generativo.").font(.caption) }
                }
                Section {
                    if !history.isEmpty {
                        Menu("Elaborazioni salvate · \(history.count)") {
                            ForEach(history.reversed()) { artifact in
                                Button("\(artifact.task?.title ?? "Elaborazione") · \(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))") { result = artifact; contextNotice = nil }
                            }
                        }
                    }
                    Button(busy ? "Elaborazione…" : configuration.engine != .offline ? "Genera con il motore scelto" : "Elabora sul dispositivo", systemImage: "sparkles") {
                        job = Task { await generate() }
                    }.disabled(busy || (configuration.engine != .offline && consentKey != configuration.consentKey))
                    if busy { Button("Annulla richiesta") { job?.cancel() } }
                }
                if let contextNotice { Section { Text(contextNotice).font(.caption).foregroundStyle(.secondary) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let result {
                    if result.references.contains(where: { reference in
                        guard reference.documentID == notebook.documentID, let id = reference.pageID,
                              let revision = reference.pageRevision else { return false }
                        return model.pages.first(where: { $0.id == id })?.revision != revision
                    }) { Section { Text("Alcune pagine sono cambiate dopo questa elaborazione. Eseguila di nuovo per aggiornarla.").foregroundStyle(.secondary) } }
                    Section("Risposta · \(result.provider)") { Text(result.text).textSelection(.enabled) }
                    Section { ShareLink("Condividi elaborazione", item: result.text) }
                    if result.task == .outline {
                        Section {
                            Button("Crea pagina mappa modificabile", systemImage: "point.3.connected.trianglepath.dotted") { Task { if await model.createMindMap(from: result) { dismiss() } } }
                            Text("Disponi fino a otto punti dello schema come caselle e collegamenti modificabili, in una nuova pagina. Il testo originale resta nelle elaborazioni salvate.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Riferimenti restituiti") {
                        ForEach(Array(result.references.enumerated()), id: \.offset) { row in
                            Button(referenceTitle(row.element)) { Task { await openSource(row.element) } }.font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Studia con le fonti")
            .task {
                do { history = try await model.workspace.artifacts(); result = history.last }
                catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: $glossary) { GlossaryPanel(model: model) }
            .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
            .onChange(of: configuration) { _, _ in job?.cancel() }
            .onDisappear { job?.cancel() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func generate() async {
        busy = true; error = nil; contextNotice = nil
        defer { busy = false }
        do {
            guard await model.flush() else { return }
            let books: [Notebook]
            if includeFolder, let folder = notebook.folderID { books = library.notebooksInFolderTree(folder) }
            else { books = [notebook] }
            var chunks: [IndexedChunk] = []
            for book in books {
                let workspace = try library.workspace(book)
                chunks += try await FileDocumentIndexingService(workspace: workspace, id: book.documentID).index(documentID: book.documentID)
            }
            guard !chunks.isEmpty else { error = "Non c’è testo da analizzare. Aggiungi testo, importa un PDF o esegui OCR/trascrizione."; return }
            let selection: SourceContext
            if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selection = SourceContext.select(chunks, spread: true)
            } else {
                let ranked: [IndexedChunk]
                if semantic { ranked = try await SemanticRetrievalService(embeddings: AppleEmbeddingService()).retrieve(question: question, from: chunks, limit: 40) }
                else { ranked = try await LexicalRetrievalService().retrieve(question: question, from: chunks, limit: 40) }
                selection = SourceContext.select(ranked)
            }
            contextNotice = "\(selection.sources.count) estratti utilizzati su \(chunks.count) disponibili. Le fonti restano consultabili; \(selection.wasTruncated || chunks.count > selection.sources.count ? "il contesto è parziale" : "gli estratti rientrano interamente nel contesto")."
            let request = AIRequest(task: task, question: question, sources: selection.sources)
            let artifact = try await AIEngineRouter.generate(request, configuration: configuration, consentKey: consentKey)
            try Task.checkCancellation()
            result = artifact
            try await model.workspace.saveArtifact(artifact)
            history.append(artifact)
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func referenceTitle(_ reference: SourceReference) -> String {
        let book = library.notebooks.first { $0.documentID == reference.documentID }?.title ?? "Documento"
        if let page = reference.pageID {
            if reference.documentID == notebook.documentID, let index = model.pages.firstIndex(where: { $0.id == page }) {
                return "\(book) · pagina \(index + 1)"
            }
            return "\(book) · pagina \(page.uuidString.prefix(8))"
        }
        if let seconds = reference.seconds { return "\(book) · \(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))" }
        return book
    }

    private func openSource(_ source: SourceReference) async {
        guard source.documentID == notebook.documentID else {
            error = "Apri \(library.notebooks.first(where: { $0.documentID == source.documentID })?.title ?? "il quaderno indicato") in un’altra scheda per consultare questa fonte."; return
        }
        if let id = source.pageID, let page = model.pages.first(where: { $0.id == id }) { await model.select(page); dismiss() }
        else if let id = source.audioSessionID, let session = model.audio?.sessions.first(where: { $0.id == id }) {
            await model.audio?.play(session, at: source.seconds ?? 0)
        }
    }
}
