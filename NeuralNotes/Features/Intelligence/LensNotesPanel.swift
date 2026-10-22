import SwiftUI
import UIKit
import NeuralNotesCore

/// Every Lens note of the notebook: tap to jump to it, edit, reduce to 💡 or open,
/// delete, and jump to the text each one explains.
@MainActor
struct LensNotesList: View {
    @Bindable var model: EditorViewModel
    @State private var query = ""
    @State private var thisPage = false
    @State private var editing: LensNoteEditTarget?

    private struct PageGroup: Identifiable { let id: UUID; let number: Int; let notes: [IndexedLensNote] }

    private var notes: [IndexedLensNote] {
        let pages = model.pages.map { $0.id == model.page?.id ? (model.page ?? $0) : $0 }
        var all = LensNotes.index(pages)
        if thisPage, let id = model.page?.id { all = all.filter { $0.pageID == id } }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { all = all.filter { $0.title.localizedStandardContains(search) || $0.body.localizedStandardContains(search) } }
        return all
    }
    private var groups: [PageGroup] {
        var result: [PageGroup] = []
        for note in notes {
            if let last = result.last, last.id == note.pageID { result[result.count - 1] = PageGroup(id: last.id, number: last.number, notes: last.notes + [note]) }
            else { result.append(PageGroup(id: note.pageID, number: note.pageNumber, notes: [note])) }
        }
        return result
    }
    private var pageHasNotes: Bool { model.page?.texts.contains(where: { $0.lensNote != nil }) == true }
    private var emptyTitle: String { query.isEmpty ? "Nessuna nota della Lente" : "Nessuna nota trovata" }
    private func header(_ group: PageGroup) -> String {
        group.id == model.page?.id ? "Pagina \(group.number) · aperta" : "Pagina \(group.number)"
    }

    var body: some View {
        VStack(spacing: 8) {
            filters
            pageCommands
            if notes.isEmpty { emptyState } else { notesList }
        }
        .sheet(item: $editing) { target in LensNoteEditor(model: model, noteID: target.id) }
    }

    // Small parts keep each expression quick for the Swift Playgrounds type checker.
    private var filters: some View {
        HStack {
            TextField("Cerca nelle note", text: $query).textFieldStyle(.roundedBorder)
            Toggle(isOn: $thisPage) { Text("Questa pagina") }.toggleStyle(.button).font(.caption)
        }.padding(.horizontal, 12).padding(.top, 8)
    }

    private var pageCommands: some View {
        HStack {
            Button("Apri tutte", systemImage: "rectangle.expand.vertical") { model.setAllLensNotes(collapsed: false) }
            Button("Riduci a 💡", systemImage: "rectangle.compress.vertical") { model.setAllLensNotes(collapsed: true) }
            Spacer()
        }.font(.caption).buttonStyle(.bordered).disabled(!pageHasNotes).padding(.horizontal, 12)
    }

    private var emptyState: some View {
        ContentUnavailableView(emptyTitle, systemImage: "note.text",
            description: Text("Sottolinea un termine con la Lente, oppure inserisci una risposta come nota: compare qui."))
    }

    private var notesList: some View {
        List {
            ForEach(groups) { group in
                Section(header(group)) {
                    ForEach(group.notes) { note in row(note) }
                }
            }
        }.listStyle(.plain)
    }

    private func row(_ note: IndexedLensNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { show(note) } label: { rowLabel(note) }
                .buttonStyle(.borderless).foregroundStyle(.primary).accessibilityHint("Mostra la nota sulla pagina")
            Button { edit(note) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).accessibilityLabel("Modifica nota")
        }
        .swipeActions(edge: .trailing) { swipeButtons(note) }
        .contextMenu { menuButtons(note) }
    }

    private func rowLabel(_ note: IndexedLensNote) -> some View {
        let icon: String = note.collapsed ? "💡" : "📝"
        return HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.subheadline.bold()).lineLimit(2)
                if !note.body.isEmpty { Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }.contentShape(Rectangle())
    }

    @ViewBuilder private func swipeButtons(_ note: IndexedLensNote) -> some View {
        let title: String = note.collapsed ? "Apri" : "Riduci"
        let icon: String = note.collapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
        Button("Elimina", systemImage: "trash", role: .destructive) { remove(note) }
        Button(title, systemImage: icon) { toggle(note) }.tint(.orange)
    }

    @ViewBuilder private func menuButtons(_ note: IndexedLensNote) -> some View {
        let title: String = note.collapsed ? "Apri sulla pagina" : "Riduci a 💡"
        Button("Modifica", systemImage: "square.and.pencil") { edit(note) }
        if note.hasSource {
            Button("Mostra il testo di origine", systemImage: "text.viewfinder") { showSource(note) }
        }
        Button(title, systemImage: "note.text") { toggle(note) }
        Button("Elimina", systemImage: "trash", role: .destructive) { remove(note) }
    }

    private func show(_ note: IndexedLensNote) { Task { await model.focusLensNote(note.textID, pageID: note.pageID) } }
    private func showSource(_ note: IndexedLensNote) { Task { await model.focusLensNote(note.textID, pageID: note.pageID, source: true) } }
    private func toggle(_ note: IndexedLensNote) { Task { await model.toggleLensNote(note.textID, pageID: note.pageID) } }
    private func remove(_ note: IndexedLensNote) { Task { await model.deleteLensNote(note.textID, pageID: note.pageID) } }

    private func edit(_ note: IndexedLensNote) {
        Task { if await model.focusLensNote(note.textID, pageID: note.pageID, outline: false) { editing = LensNoteEditTarget(id: note.textID) } }
    }
}

/// Edit a Lens note: title, text, color, icon state; jump to its text, ask again or delete it.
@MainActor
struct LensNoteEditor: View {
    let model: EditorViewModel
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TextElement(text: "")
    @State private var original: TextElement?
    @State private var color = LensNoteColor.yellow
    @State private var collapsed = false
    @State private var confirmDelete = false

    private var note: TextElement? { model.page?.texts.first { $0.id == noteID && $0.lensNote != nil } }
    private var paper: UIColor { UIColor(red: color.ink.red, green: color.ink.green, blue: color.ink.blue, alpha: 1) }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Nota della Lente").navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
                .confirmationDialog("Eliminare questa nota?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Elimina nota", role: .destructive) { delete() }
                } message: { Text("Puoi recuperarla con Annulla.") }
        }
        .onAppear(perform: load)
    }

    // Small parts keep each expression quick for the Swift Playgrounds type checker.
    private var form: some View {
        Form {
            if let note { fields(note) }
            else { Text("La nota non è sulla pagina aperta: aprila dall’elenco delle note.").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func fields(_ note: TextElement) -> some View {
        Section {
            RichTextEditor(text: $draft, paperColor: paper).frame(minHeight: 260)
                .accessibilityIdentifier("lensNoteRichEditor")
        } header: { Text("Titolo e testo") } footer: {
            Text("La prima riga è il titolo. Seleziona il testo per usare grassetto, corsivo ed elenchi: lo stile resta nella nota e nel PDF esportato.")
        }
        Section("Aspetto") {
            Picker("Colore", selection: $color) { ForEach(LensNoteColor.allCases) { item in Text(item.title).tag(item) } }
                .pickerStyle(.segmented)
            Toggle("Ridotta a 💡 sulla pagina", isOn: $collapsed)
        }
        Section { actions(note) }
        if let origin = note.lensNote?.origin { Section { Text(origin).font(.caption).foregroundStyle(.secondary) } }
    }

    @ViewBuilder private func actions(_ note: TextElement) -> some View {
        if note.lensNote?.source != nil {
            Button("Mostra il testo di origine", systemImage: "text.viewfinder") { showSource() }
        }
        Button("Chiedi ancora alla Lente", systemImage: "sparkle.magnifyingglass") { askAgain() }
        Button("Elimina nota", systemImage: "trash", role: .destructive) { confirmDelete = true }
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Salva") { save(); dismiss() }.disabled(note == nil) }
    }

    private func showSource() {
        save(); dismiss()
        Task { await model.focusLensNote(noteID, source: true) }
    }

    private func askAgain() {
        save(); dismiss()
        model.askLensAgain(noteID)
    }

    private func delete() {
        if let pageID = model.page?.id { Task { await model.deleteLensNote(noteID, pageID: pageID) } }
        dismiss()
    }

    private func load() {
        guard let note, let info = note.lensNote else { return }
        guard original == nil else { return }
        draft = note; original = note; color = LensNoteColor(note.background); collapsed = info.isCollapsed
    }

    private func save() {
        guard let current = note, let info = current.lensNote, original != nil else { return }
        let rewritten = draft.text != current.text || draft.rtf != current.rtf
        let recolored = color != LensNoteColor(current.background)
        let folded = collapsed != info.isCollapsed
        guard rewritten || recolored || folded else { return }
        model.updateLensNote(noteID, edited: draft, color: color, collapsed: collapsed)
    }
}
