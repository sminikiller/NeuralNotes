import SwiftUI
import NeuralNotesCore

private struct NotebookTab: Identifiable {
    let notebook: Notebook
    let model: EditorViewModel
    var id: UUID { notebook.id }
}

/// Only the active tab mounts a PencilKit canvas. Inactive documents keep their
/// editor state, while audio is explicitly paused before leaving a tab.
@MainActor
struct NotebookDesk: View {
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabs: [NotebookTab]
    @State private var selected: UUID
    @State private var choosing = false
    @State private var switching = false
    @State private var error: String?
    @SceneStorage("desk.session") private var savedSession = ""
    @AppStorage("desk.lastSession") private var lastSession = ""
    @State private var restored = false
    @SceneStorage("editor.focus") private var focus = false

    init(notebook: Notebook, model: EditorViewModel, library: LibraryViewModel) {
        self.library = library
        _tabs = State(initialValue: [NotebookTab(notebook: notebook, model: model)])
        _selected = State(initialValue: notebook.id)
    }

    private var active: NotebookTab? { tabs.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 0) {
            if !focus { HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            HStack(spacing: 10) {
                                Button { Task { await select(tab.id) } } label: {
                                    Label(tab.notebook.title, systemImage: "book.closed")
                                        .lineLimit(1).frame(maxWidth: 200)
                                }.buttonStyle(.plain)
                                Button { Task { await close(tab.id) } } label: { Image(systemName: "xmark").font(.caption) }
                                    .buttonStyle(.plain).accessibilityLabel("Chiudi \(tab.notebook.title)")
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(selected == tab.id ? Brand.accent.opacity(0.18) : Brand.surface,
                                in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(.horizontal).padding(.vertical, 6)
                }
                Button { choosing = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Apri un altro quaderno in una scheda")
            }.background(.bar).disabled(switching) }
            if let active {
                EditorView(model: active.model, notebook: library.notebooks.first(where: { $0.id == active.id }) ?? active.notebook, library: library, returnToLibrary: {
                    await closeAll()
                }).id(active.id).disabled(switching)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: focus)
        .interactiveDismissDisabled()
        .task {
            guard !restored else { return }; restored = true
            if let data = savedSession.data(using: .utf8), let stored = try? JSONDecoder().decode(DeskSession.self, from: data) {
                let valid = stored.available(in: Set(library.notebooks.map(\.id)))
                for id in valid.notebookIDs where !tabs.contains(where: { $0.id == id }) {
                    if tabs.count < 6, let notebook = library.notebooks.first(where: { $0.id == id }), let workspace = try? library.workspace(notebook) {
                        tabs.append(NotebookTab(notebook: notebook, model: EditorViewModel(workspace: workspace)))
                    }
                }
            }
            persist()
        }
        .onChange(of: selected) { _, _ in persist() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { for tab in tabs { tab.model.audio?.transcriptionTask?.cancel() } }
        }
        .onChange(of: tabs.map(\.id)) { _, _ in persist() }
        .sheet(isPresented: $choosing) {
            NavigationStack {
                List(library.notebooks) { notebook in
                    Button {
                        choosing = false
                        Task { await open(notebook) }
                    } label: { Label(notebook.title, systemImage: "book.closed") }
                }
                .navigationTitle("Apri una scheda")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { choosing = false } } }
            }
        }
        .alert("Schede", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func suspend(_ tab: NotebookTab) async -> Bool {
        guard !tab.model.navigating else { error = "Attendi il completamento dell’operazione nel quaderno."; return false }
        await tab.model.audio?.suspendForTabChange()
        guard await tab.model.flush() else {
            error = tab.model.error
            if selected == tab.id { tab.model.audio?.resumeAfterTabChange() }
            return false
        }
        library.didEdit(tab.notebook)
        return true
    }

    private func select(_ id: UUID) async {
        guard !switching, selected != id else { return }
        switching = true; defer { switching = false }
        if let active, !(await suspend(active)) { return }
        selected = id
        active?.model.audio?.resumeAfterTabChange()
    }

    private func open(_ notebook: Notebook) async {
        if tabs.contains(where: { $0.id == notebook.id }) { await select(notebook.id); return }
        guard tabs.count < 6 else { error = "Puoi tenere aperti fino a sei quaderni. Chiudi una scheda per aprirne un’altra."; return }
        guard !switching else { return }
        switching = true; defer { switching = false }
        if let active, !(await suspend(active)) { return }
        do {
            tabs.append(NotebookTab(notebook: notebook, model: EditorViewModel(workspace: try library.workspace(notebook))))
            selected = notebook.id
        } catch { active?.model.audio?.resumeAfterTabChange(); self.error = error.localizedDescription }
    }

    private func close(_ id: UUID) async {
        guard !switching, let tab = tabs.first(where: { $0.id == id }) else { return }
        if tabs.count == 1 { await closeAll(); return }
        switching = true; defer { switching = false }
        guard await suspend(tab) else { return }
        guard await tab.model.close() else { return }
        tabs.removeAll { $0.id == id }
        if selected == id, let next = tabs.last { selected = next.id; next.model.audio?.resumeAfterTabChange() }
    }

    private func closeAll() async {
        guard !switching else { return }
        switching = true; defer { switching = false }
        for tab in tabs {
            if !(await suspend(tab)) { active?.model.audio?.resumeAfterTabChange(); return }
        }
        persist()
        for tab in tabs { guard await tab.model.close() else { return } }
        dismiss()
    }

    private func persist() {
        let value = DeskSession(notebookIDs: tabs.map(\.id), selectedID: selected)
        if let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) {
            savedSession = text; lastSession = text
        }
    }
}
