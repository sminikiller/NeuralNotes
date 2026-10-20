import SwiftUI
import NeuralNotesCore

@MainActor
struct NotebookOverview: View {
    let notebookID: UUID
    let model: LibraryViewModel
    @State private var manifest: DocumentManifest?
    @State private var openError: String?
    @State private var isEditing = false
    @State private var editor: EditorViewModel?
    @State private var customizingCover = false

    private var notebook: Notebook? { model.notebooks.first { $0.id == notebookID } }

    var body: some View {
        Group {
            if let notebook {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LibraryNotebookCover(notebook: notebook, library: model).frame(maxWidth: 360)
                        Text(notebook.title).font(.largeTitle.bold()).accessibilityIdentifier("openedNotebookTitle")
                        if let openError {
                            Label(openError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            Button("Riprova") { load(notebook) }
                        } else if let manifest {
                            Label("Quaderno salvato sul dispositivo", systemImage: "checkmark.shield")
                                .foregroundStyle(Brand.accent).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("documentIntegrityStatus")
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Creato", value: notebook.createdAt.formatted(date: .abbreviated, time: .shortened))
                                LabeledContent("Modificato", value: notebook.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                LabeledContent("Pagine", value: String(manifest.pageIDs.count))
                                LabeledContent("Formato nativo", value: "NeuralNotes v\(manifest.schemaVersion)")
                            }
                            .padding().background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                            Button {
                                do { editor = EditorViewModel(workspace: try model.workspace(notebook)) }
                                catch { openError = error.localizedDescription }
                            } label: { Label("Scrivi e studia", systemImage: "pencil.tip.crop.circle") }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .accessibilityIdentifier("openEditorButton")
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading).padding(28).frame(maxWidth: .infinity)
                }
                .background(Brand.background)
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Copertina", systemImage: "paintpalette") { customizingCover = true }
                        Button("Modifica", systemImage: "square.and.pencil") { isEditing = true }
                            .accessibilityIdentifier("editOpenedNotebookButton")
                    }
                }
                .task(id: notebook.id) { load(notebook) }
                .sheet(isPresented: $customizingCover) { PhotoCoverPanel(notebook: notebook, library: model) }
                .onChange(of: editor == nil) { _, closed in if closed { load(notebook) } }
                .sheet(isPresented: $isEditing) { NotebookForm(model: model, notebook: notebook) }
                .fullScreenCover(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
                    if let editor { NotebookDesk(notebook: notebook, model: editor, library: model) }
                }
            } else {
                ContentUnavailableView("Quaderno non disponibile", systemImage: "book.closed")
            }
        }
    }

    private func load(_ notebook: Notebook) {
        do { manifest = try model.open(notebook); openError = nil }
        catch { manifest = nil; openError = error.localizedDescription }
    }
}
