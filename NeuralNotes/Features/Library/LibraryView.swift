import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NeuralNotesCore

private enum LibrarySheet: Identifiable {
    case createNotebook, editNotebook(Notebook), createFolder(UUID?), renameFolder(LibraryFolder), diagnostics, cover(Notebook), storage(Notebook), recovery
    var id: String {
        switch self {
        case .createNotebook: return "new-notebook"
        case .editNotebook(let notebook): return "edit-\(notebook.id)"
        case .createFolder(let parent): return "new-folder-\(parent?.uuidString ?? "root")"
        case .renameFolder(let folder): return "folder-\(folder.id)"
        case .diagnostics: return "diagnostics"
        case .cover(let notebook): return "cover-\(notebook.id)"
        case .storage(let notebook): return "storage-\(notebook.id)"
        case .recovery: return "recovery"
        }
    }
}

@MainActor
struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("library.usesGrid") private var usesGrid = true
    @AppStorage("library.sort") private var persistedSort = LibrarySort.modified.rawValue
    @State private var sheet: LibrarySheet?
    @State private var pendingDeletion: Notebook?
    @State private var pendingFolderDeletion: LibraryFolder?
    @State private var path: [UUID] = []
    @State private var showIntegrityReport = false
    @State private var importingNotebook = false
    @SceneStorage("desk.session") private var savedSession = ""
    @AppStorage("desk.lastSession") private var lastSession = ""
    @State private var resumeNotebook: Notebook?
    @State private var resumeEditor: EditorViewModel?
    @State private var checkedResume = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                collection
                    .navigationDestination(for: UUID.self) { id in
                        NotebookOverview(notebookID: id, model: model)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard !checkedResume else { return }; checkedResume = true
            await Task.yield()
            // SceneStorage may not be flushed before the process is killed.
            // Only a sole window may use the durable last-desk fallback; new
            // windows must not reopen the document owned by an existing scene.
            var candidates = [savedSession]
            if UIApplication.shared.openSessions.count <= 1 { candidates.append(lastSession) }
            for candidate in candidates {
                guard let data = candidate.data(using: .utf8), let stored = try? JSONDecoder().decode(DeskSession.self, from: data) else { continue }
                let valid = stored.available(in: Set(model.notebooks.map(\.id)))
                if let notebook = model.notebooks.first(where: { $0.id == valid.selectedID }) {
                    do {
                        resumeEditor = EditorViewModel(workspace: try model.workspace(notebook))
                        resumeNotebook = notebook
                    } catch { model.errorMessage = error.localizedDescription }
                    break
                }
            }
        }
        .fullScreenCover(item: $resumeNotebook, onDismiss: { resumeEditor = nil }) { notebook in
            if let resumeEditor {
                NotebookDesk(notebook: notebook, model: resumeEditor, library: model)
            }
        }
        .fileImporter(isPresented: $importingNotebook, allowedContentTypes: [.pdf, .data, .folder, .package]) { result in
            switch result {
            case .success(let url): Task { await model.importNotebook(from: url) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .createNotebook: NotebookForm(model: model)
            case .editNotebook(let notebook): NotebookForm(model: model, notebook: notebook)
            case .createFolder(let parent): FolderForm(model: model, folder: nil, parentID: parent)
            case .renameFolder(let folder): FolderForm(model: model, folder: folder, parentID: nil)
            case .diagnostics: DiagnosticsPanel()
            case .cover(let notebook): PhotoCoverPanel(notebook: notebook, library: model)
            case .storage(let notebook):
                if let workspace = try? model.workspace(notebook) { StoragePanel(workspace: workspace, metadata: notebook) }
            case .recovery: RecoveryPanel(library: model)
            }
        }
        .alert("Operazione non riuscita", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Eliminare il quaderno?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("Elimina quaderno", role: .destructive) {
                    if let notebook = pendingDeletion { model.delete(notebook) }
                    pendingDeletion = nil
                }
                Button("Annulla", role: .cancel) { pendingDeletion = nil }
            } message: { Text("Puoi annullare l’ultima eliminazione dalla libreria. I file originali vengono conservati.") }
        .confirmationDialog("Eliminare la cartella vuota?", isPresented: Binding(
            get: { pendingFolderDeletion != nil }, set: { if !$0 { pendingFolderDeletion = nil } }), titleVisibility: .visible) {
                Button("Elimina cartella", role: .destructive) {
                    if let folder = pendingFolderDeletion { model.deleteFolder(folder) }
                    pendingFolderDeletion = nil
                }
            }
        .alert("Integrità dei documenti", isPresented: $showIntegrityReport) {
            Button("OK", role: .cancel) { }
        } message: { Text(model.integrityIssues.joined(separator: "\n\n")) }
        .onChange(of: model.scope) { _, _ in path = [] }
        .onChange(of: LibraryRevision.shared.value) { _, _ in model.perform { try model.reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.perform { try model.reload() } }
        }
        .onChange(of: model.sort) { _, value in persistedSort = value.rawValue }
        .onAppear { model.sort = LibrarySort(rawValue: persistedSort) ?? .modified }
    }

    private var sidebar: some View {
        List(selection: $model.scope) {
            Section {
                Label("Tutti i quaderni", systemImage: "books.vertical").tag(LibraryScope.all)
                Label("Preferiti", systemImage: "star").tag(LibraryScope.favorites)
                Label("Cestino", systemImage: "trash").tag(LibraryScope.trash)
            }
            Section {
                ForEach(model.folderRows, id: \.folder.id) { row in
                    Label(row.folder.title, systemImage: "folder")
                        .padding(.leading, CGFloat(min(row.depth, 6)) * 12)
                        .tag(LibraryScope.folder(row.folder.id))
                        .accessibilityLabel("Cartella \(row.folder.title), livello \(row.depth + 1)")
                        .contextMenu {
                            Button("Nuova sottocartella", systemImage: "folder.badge.plus") { sheet = .createFolder(row.folder.id) }
                            Button("Rinomina", systemImage: "pencil") { sheet = .renameFolder(row.folder) }
                            Button("Elimina", systemImage: "trash", role: .destructive) { pendingFolderDeletion = row.folder }
                        }
                }
                Button { sheet = .createFolder(nil) } label: {
                    Label("Nuova cartella", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("newFolderButton")
            } header: { Text("Cartelle") }
            Section {
                Label("Sul tuo iPad", systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { sheet = .diagnostics } label: { Label("Verifica sul dispositivo", systemImage: "checkmark.seal") }
                Button { sheet = .recovery } label: { Label("Recupero quaderni", systemImage: "arrow.uturn.backward.circle") }
                Button { importingNotebook = true } label: { Label("Importa PDF o quaderno", systemImage: "square.and.arrow.down") }
                    .disabled(model.importing)
                if model.importing { ProgressView("Importazione del quaderno…") }
            } footer: {
                Text("I tuoi quaderni, uno spazio per le idee.")
            }
        }
        .navigationTitle("NeuralNotes")
        .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
    }

    private var collection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SPAZIO ALLE IDEE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Brand.accent)
                        Text(model.title).font(.largeTitle.bold())
                        Text("\(model.visibleNotebooks.count) quaderni · salvati sul dispositivo")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !model.integrityIssues.isEmpty {
                    Button { showIntegrityReport = true } label: {
                        Label("Alcuni documenti richiedono attenzione", systemImage: "exclamationmark.triangle")
                    }
                    .buttonStyle(.bordered)
                }
                if model.scope != .trash && model.query.isEmpty {
                    LibraryDashboard(notebooks: model.visibleNotebooks,
                        recent: model.recentNotebooks.filter { recent in model.visibleNotebooks.contains { $0.id == recent.id } },
                        library: model, create: { sheet = .createNotebook }, importFile: { importingNotebook = true }, open: { resumeNotebook = $0 })
                }
                if model.visibleNotebooks.isEmpty {
                    emptyState.frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if usesGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 18)], spacing: 22) {
                        ForEach(model.visibleNotebooks) { notebook in
                            if model.scope == .trash { restoreButton(notebook) }
                            else { notebookLink(notebook, compact: false) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.visibleNotebooks) { notebook in
                            if model.scope == .trash { restoreButton(notebook) }
                            else { notebookLink(notebook, compact: true) }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Brand.background)
        .navigationTitle("Libreria")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Cerca un quaderno")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { importingNotebook = true } label: { Label("Importa PDF o quaderno", systemImage: "square.and.arrow.down") }
                    .disabled(model.importing)
                Menu {
                    Picker("Ordina per", selection: $model.sort) {
                        ForEach(LibrarySort.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                } label: { Label("Ordina", systemImage: "arrow.up.arrow.down") }
                Button { usesGrid.toggle() } label: {
                    Label(usesGrid ? "Vista elenco" : "Vista griglia", systemImage: usesGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityIdentifier("toggleLibraryLayoutButton")
                Button { sheet = .createNotebook } label: { Label("Nuovo quaderno", systemImage: "plus") }
                    .accessibilityIdentifier("newNotebookButton")
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.lastDeletedID != nil {
                HStack {
                    Text("Quaderno eliminato").font(.callout)
                    Spacer()
                    Button("Annulla eliminazione") { model.restoreLastDeleted() }
                }
                .padding().background(.regularMaterial)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            ContentUnavailableView {
                Label(model.scope == .favorites ? "I tuoi preferiti" : "La prossima idea parte da qui", systemImage: "book.closed")
            } description: {
                Text(model.scope == .favorites ? "Aggiungi un quaderno ai preferiti dal suo menu." : "Crea un quaderno e scegli una copertina per iniziare.")
            } actions: {
                Button("Crea un quaderno") { sheet = .createNotebook }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func notebookLink(_ notebook: Notebook, compact: Bool) -> some View {
        NavigationLink(value: notebook.id) {
            Group {
                if compact {
                    HStack(spacing: 16) {
                        LibraryNotebookCover(notebook: notebook, library: model, compact: true)
                        notebookCaption(notebook)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14).background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        LibraryNotebookCover(notebook: notebook, library: model)
                        notebookCaption(notebook).padding(.horizontal, 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notebook-\(notebook.id.uuidString)")
        .accessibilityLabel(notebook.title)
        .accessibilityHint("Apri il quaderno. Altre azioni nel menu contestuale.")
        .contextMenu {
            Button("Modifica e rinomina", systemImage: "pencil") { sheet = .editNotebook(notebook) }
            Button("Personalizza copertina", systemImage: "paintpalette") { sheet = .cover(notebook) }
            Button("Spazio e recupero", systemImage: "externaldrive") { sheet = .storage(notebook) }
            Button(notebook.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: "star") { model.toggleFavorite(notebook) }
            Button("Duplica", systemImage: "plus.square.on.square") { Task { await model.duplicate(notebook) } }
            Button("Elimina", systemImage: "trash", role: .destructive) { pendingDeletion = notebook }
        }
        .accessibilityAction(named: "Rinomina") { sheet = .editNotebook(notebook) }
        .accessibilityAction(named: "Preferiti") { model.toggleFavorite(notebook) }
    }

    private func notebookCaption(_ notebook: Notebook) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(notebook.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                if notebook.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(Brand.accent) }
            }
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func restoreButton(_ notebook: Notebook) -> some View {
        Button { model.restore(notebook) } label: {
            VStack(alignment: .leading, spacing: 12) {
                NotebookCoverView(notebook: notebook, compact: true)
                Text(notebook.title).font(.headline)
                Label("Ripristina quaderno", systemImage: "arrow.uturn.backward")
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
