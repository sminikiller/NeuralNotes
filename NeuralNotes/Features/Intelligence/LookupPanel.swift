import SwiftUI
import NeuralNotesCore

@MainActor
struct LookupPanel: View {
    let model: EditorViewModel
    let sources: [IndexedChunk]
    let configuration: AIEngineConfiguration
    let consentKey: String?
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var card: LookupCard?
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
                    if configuration.lookupURL != nil {
                        Button("Crea scheda dalle fonti", systemImage: "sparkles") { generate() }
                            .disabled(busy || !LookupRequest(term: term, sources: sources).isValid || consentKey != configuration.consentKey)
                        if consentKey != configuration.consentKey { Text("Abilita l’invio delle fonti nella Connessione AI della Lente per questo pannello di studio.").font(.caption) }
                    } else { Text("Le schede strutturate usano il backend personale aggiornato. Il dizionario di sistema resta disponibile; gli altri motori possono definire il termine nella chat della Lente.").font(.caption) }
                }
                if busy { ProgressView("Preparazione della scheda…"); Button("Annulla") { job?.cancel() } }
                if let error { Text(error).foregroundStyle(.red) }
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
                        Button("Inserisci nel foglio", systemImage: "text.badge.plus") { model.mutatePage("Inserisci definizione") { $0.texts.append(TextElement(text: card.text)) }; dismiss() }
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
                .task { term = String(sources.first?.text.prefix(120) ?? "") }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
                .onDisappear { job?.cancel() }
                .onChange(of: term) { _, _ in card = nil; error = nil }
        }
    }
    private func generate() {
        guard !busy else { return }; busy = true; error = nil
        let input = LookupRequest(term: term, sources: sources)
        job = Task {
            defer { busy = false }
            do {
                let result = try await AIEngineRouter.lookup(input, configuration: configuration, consentKey: consentKey)
                try Task.checkCancellation(); try await model.workspace.saveArtifact(result.artifact); card = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
