import SwiftUI
import NeuralNotesCore

@MainActor
struct GlossaryPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [GlossaryEntry] = []
    @State private var draft: GlossaryEntry?
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                ForEach(entries.filter { query.isEmpty || $0.term.localizedStandardContains(query) || $0.definition.localizedStandardContains(query) }) { entry in
                    Button { draft = entry } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(entry.term).font(.headline); Text(entry.definition).lineLimit(3).foregroundStyle(.secondary) }
                    }.contextMenu {
                        Button("Crea flashcard", systemImage: "rectangle.on.rectangle") { Task { await card(entry) } }
                        Button("Elimina", systemImage: "trash", role: .destructive) { Task { await remove(entry) } }
                    }
                }
                if entries.isEmpty { Text("Conserva qui definizioni e fonti dalla Lente AI, oppure aggiungi una voce a mano.").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Glossario del quaderno").searchable(text: $query)
                .task { await reload() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Aggiungi", systemImage: "plus") { draft = GlossaryEntry(term: "", definition: "", references: []) } }
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                }
                .sheet(item: $draft, onDismiss: { Task { await reload() } }) { entry in GlossaryEntryEditor(model: model, entry: entry) }
        }
    }
    private func reload() async { do { entries = try await model.workspace.catalog().glossary ?? [] } catch { self.error = error.localizedDescription } }
    private func remove(_ entry: GlossaryEntry) async { do { try await model.workspace.removeGlossaryEntry(entry.id); await reload() } catch { self.error = error.localizedDescription } }
    private func card(_ entry: GlossaryEntry) async {
        guard let reference = entry.references.first else { error = "Questa voce non ha una fonte collegata. Salvala dalla Lente per crearne una flashcard con riferimento."; return }
        do { try await model.workspace.addStudyCards([StudyCard(question: entry.term, answer: entry.definition, source: reference)]) }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
private struct GlossaryEntryEditor: View {
    let model: EditorViewModel
    @State var entry: GlossaryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Termine", text: $entry.term)
                TextEditor(text: $entry.definition).frame(minHeight: 220).accessibilityLabel("Definizione")
                Button("Dizionario di sistema", systemImage: "character.book.closed") { SystemDictionary.open(term: entry.term, from: model.pagePresenter as? UIView) }.disabled(entry.term.isEmpty)
                ForEach(Array(entry.references.enumerated()), id: \.offset) { row in
                    if let page = row.element.pageID, let index = model.pages.firstIndex(where: { $0.id == page }) {
                        Button("Fonte · pagina \(index + 1)") { Task { await model.select(model.pages[index]); dismiss() } }
                    } else if let seconds = row.element.seconds { Text("Fonte audio · \(TranscriptText.clock(seconds))") }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Voce del glossario")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") {
                        entry.updatedAt = Date()
                        Task { do { try await model.workspace.saveGlossaryEntry(entry); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(!entry.isValid) }
                }
        }
    }
}
