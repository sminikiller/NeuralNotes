import SwiftUI
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
            HStack {
                TextField("Cerca nelle note", text: $query).textFieldStyle(.roundedBorder)
                Toggle(isOn: $thisPage) { Text("Questa pagina") }.toggleStyle(.button).font(.caption)
            }.padding(.horizontal, 12).padding(.top, 8)
            HStack {
                Button("Apri tutte", systemImage: "rectangle.expand.vertical") { model.setAllLensNotes(collapsed: false) }
                Button("Riduci a 💡", systemImage: "rectangle.compress.vertical") { model.setAllLensNotes(collapsed: true) }
                Spacer()
            }.font(.caption).buttonStyle(.bordered).disabled(!pageHasNotes).padding(.horizontal, 12)
            if notes.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "note.text",
                    description: Text("Sottolinea un termine con la Lente, oppure inserisci una risposta come nota: compare qui."))
            } else {
                List {
                    ForEach(groups) { group in
                        Section(header(group)) {
                            ForEach(group.notes) { note in row(note) }
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .sheet(item: $editing) { target in LensNoteEditor(model: model, noteID: target.id) }
    }

    private func row(_ note: IndexedLensNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { Task { await model.focusLensNote(note.textID, pageID: note.pageID) } } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(note.collapsed ? "💡" : "📝").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).font(.subheadline.bold()).lineLimit(2)
                        if !note.body.isEmpty { Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.borderless).foregroundStyle(.primary).accessibilityHint("Mostra la nota sulla pagina")
            Button { edit(note) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).accessibilityLabel("Modifica nota")
        }
        .swipeActions(edge: .trailing) {
            Button("Elimina", systemImage: "trash", role: .destructive) { Task { await model.deleteLensNote(note.textID, pageID: note.pageID) } }
            Button(note.collapsed ? "Apri" : "Riduci", systemImage: note.collapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
                Task { await model.toggleLensNote(note.textID, pageID: note.pageID) }
            }.tint(.orange)
        }
        .contextMenu {
            Button("Modifica", systemImage: "square.and.pencil") { edit(note) }
            if note.hasSource {
                Button("Mostra il testo di origine", systemImage: "text.viewfinder") { Task { await model.focusLensNote(note.textID, pageID: note.pageID, source: true) } }
            }
            Button(note.collapsed ? "Apri sulla pagina" : "Riduci a 💡", systemImage: "note.text") { Task { await model.toggleLensNote(note.textID, pageID: note.pageID) } }
            Button("Elimina", systemImage: "trash", role: .destructive) { Task { await model.deleteLensNote(note.textID, pageID: note.pageID) } }
        }
    }

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
    @State private var title = ""
    @State private var content = ""
    @State private var color = LensNoteColor.yellow
    @State private var collapsed = false
    @State private var confirmDelete = false

    private var note: TextElement? { model.page?.texts.first { $0.id == noteID && $0.lensNote != nil } }

    var body: some View {
        NavigationStack {
            Form {
                if let note {
                    Section("Titolo") { TextField("Titolo della nota", text: $title) }
                    Section("Testo") { TextEditor(text: $content).frame(minHeight: 180) }
                    Section("Aspetto") {
                        Picker("Colore", selection: $color) { ForEach(LensNoteColor.allCases) { item in Text(item.title).tag(item) } }
                            .pickerStyle(.segmented)
                        Toggle("Ridotta a 💡 sulla pagina", isOn: $collapsed)
                    }
                    Section {
                        if note.lensNote?.source != nil {
                            Button("Mostra il testo di origine", systemImage: "text.viewfinder") {
                                save(); dismiss(); Task { await model.focusLensNote(noteID, source: true) }
                            }
                        }
                        Button("Chiedi ancora alla Lente", systemImage: "sparkle.magnifyingglass") { save(); dismiss(); model.askLensAgain(noteID) }
                        Button("Elimina nota", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                    if let origin = note.lensNote?.origin { Section { Text(origin).font(.caption).foregroundStyle(.secondary) } }
                } else {
                    Text("La nota non è sulla pagina aperta: aprila dall’elenco delle note.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nota della Lente").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save(); dismiss() }.disabled(note == nil) }
            }
            .confirmationDialog("Eliminare questa nota?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina nota", role: .destructive) {
                    if let pageID = model.page?.id { Task { await model.deleteLensNote(noteID, pageID: pageID) } }
                    dismiss()
                }
            } message: { Text("Puoi recuperarla con Annulla.") }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let note, let info = note.lensNote else { return }
        title = info.title; content = LensNotes.body(of: note); color = LensNoteColor(note.background); collapsed = info.isCollapsed
    }

    private func save() {
        guard let current = note, let info = current.lensNote else { return }
        let changed = title != info.title || content != LensNotes.body(of: current) || color != LensNoteColor(current.background) || collapsed != info.isCollapsed
        if changed { model.updateLensNote(noteID, title: title, body: content, color: color, collapsed: collapsed) }
    }
}
