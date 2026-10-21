import SwiftUI
import NeuralNotesCore

@MainActor
struct LookupPanel: View {
    let model: EditorViewModel
    let sources: [IndexedChunk]
    let configuration: AIEngineConfiguration
    let consentKey: String?
    var initialTerm: String? = nil
    var onConfigure: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var card: LookupCard?
    @State private var research: AIArtifact?
    @State private var error: String?
    @State private var busy = false
    @State private var job: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("Termine selezionato") {
                    TextField("Termine da definire", text: $term).disabled(busy)
                    Text("\(sources.count) fonti · \(configuration.destination)").font(.caption).foregroundStyle(.secondary)
                    Button("Dizionario di sistema", systemImage: "character.book.closed") { SystemDictionary.open(term: term, from: model.pagePresenter as? UIView) }.disabled(term.isEmpty)
                    if let webURL {
                        Link(destination: webURL) { Label("Apri ricerca nel browser", systemImage: "safari") }
                        Text("Il browser riceve solo il termine cercato.").font(.caption).foregroundStyle(.secondary)
                    }
                    if configuration.lookupURL != nil {
                        Button("Crea scheda dalle fonti", systemImage: "sparkles") { generate() }
                            .disabled(busy || !LookupRequest(term: term, sources: sources).isValid || consentKey != configuration.consentKey)
                        Button("Cerca sul web con fonti", systemImage: "globe") { generateResearch() }
                            .disabled(busy || !WebResearchRequest(term: term).isValid || consentKey != configuration.consentKey)
                        Text("La ricerca web invia solo il termine, non la pagina o la registrazione. Richiede l’abilitazione sul backend e può avere costi aggiuntivi. Le risposte dalle fonti del quaderno restano separate.").font(.caption).foregroundStyle(.secondary)
                        if consentKey != configuration.consentKey { Text("Abilita l’invio delle fonti nella Connessione AI della Lente per questo pannello di studio.").font(.caption) }
                    } else { Text("Le schede strutturate usano il backend personale aggiornato. Il dizionario di sistema resta disponibile; gli altri motori possono definire il termine nella chat della Lente.").font(.caption) }
                }
                if busy { ProgressView("Preparazione della scheda…"); Button("Annulla") { job?.cancel() } }
                if let error { Text(error).foregroundStyle(.red) }
                if let research {
                    Section("Ricerca web · \(research.provider)") {
                        Text("Fonti raccolte: \(research.createdAt.formatted(date: .abbreviated, time: .shortened)) · riutilizzabili per un’ora").font(.caption).foregroundStyle(.secondary)
                        CitedAnswer(artifact: research)
                        Button("Inserisci risposta e collegamenti", systemImage: "text.badge.plus") { if model.insertAIAnswer(research) { dismiss() } }
                            .disabled(model.hasActiveStroke || model.navigating || model.loading)
                        ShareLink("Condividi ricerca", item: research.citedRuns.map(\.text).joined())
                    }
                }
                if let card {
                    Section("Definizione") { Text(card.definition).textSelection(.enabled) }
                    if !card.explanation.isEmpty { Section("Spiegazione") { Text(card.explanation).textSelection(.enabled) } }
                    if !card.examples.isEmpty { Section("Esempi") { ForEach(Array(card.examples.enumerated()), id: \.offset) { Text($0.element) } } }
                    if !card.relatedTerms.isEmpty { Section("Termini correlati") { Text(card.relatedTerms.joined(separator: " · ")) } }
                    Section {
                        Button("Salva nel glossario", systemImage: "character.book.closed") {
                            Task {
                                do { try await model.workspace.saveGlossaryEntry(GlossaryEntry(term: card.term, definition: String(card.text.prefix(16000)), references: card.references)); model.status = "Definizione salvata nel glossario"; dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        Button("Inserisci nel foglio", systemImage: "text.badge.plus") { if model.insertAIAnswer(card.artifact) { dismiss() } }.disabled(model.hasActiveStroke || model.navigating || model.loading)
                    }
                    Section("Fonti") {
                        ForEach(Array(card.references.enumerated()), id: \.offset) { row in
                            if let pageID = row.element.pageID, let index = model.pages.firstIndex(where: { $0.id == pageID }) {
                                Button("[\(row.offset + 1)] Pagina \(index + 1)") { Task { await model.select(model.pages[index]); dismiss() } }
                            } else if let time = row.element.seconds { Text("[\(row.offset + 1)] Audio · \(TranscriptText.clock(time))") }
                        }
                    }
                }
            }.navigationTitle("Definizione con fonti")
                .task { term = initialTerm ?? String(sources.first?.text.prefix(120) ?? "") }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                    if let onConfigure { ToolbarItem(placement: .primaryAction) { Button("Connessione AI", systemImage: "network", action: onConfigure) } }
                }
                .onDisappear { job?.cancel() }
                .onChange(of: term) { _, _ in card = nil; research = nil; error = nil }
        }
    }
    private var webURL: URL? {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200 else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
    private func generate() {
        guard !busy else { return }; busy = true; error = nil
        let input = LookupRequest(term: term, sources: sources)
        job = Task {
            defer { busy = false }
            do {
                let result = try await AIEngineRouter.lookup(input, configuration: configuration, consentKey: consentKey)
                try Task.checkCancellation(); card = result
                do { try await model.workspace.saveArtifact(result.artifact) }
                catch { self.error = "Risposta visibile, ma non salvata: \(error.localizedDescription)" }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func generateResearch() {
        guard !busy else { return }; busy = true; error = nil
        let input = WebResearchRequest(term: term)
        job = Task {
            defer { busy = false }
            do {
                let key = input.cacheKey(configuration: configuration)
                let value: AIArtifact
                if let cached = try? await model.workspace.cachedLensAnswer(key: key),
                   let valid = try? cached.validatedWebResearch(), (0..<3600).contains(Date().timeIntervalSince(valid.createdAt)) { value = valid }
                else {
                    value = try await AIEngineRouter.research(input, configuration: configuration, consentKey: consentKey)
                    try Task.checkCancellation()
                    if value.text.count <= 16_000 { try? await model.workspace.cacheLensAnswer(key: key, artifact: value) }
                }
                try Task.checkCancellation(); research = value
                do { try await model.workspace.saveArtifact(value) }
                catch { self.error = "Risposta visibile, ma non salvata: \(error.localizedDescription)" }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
