import SwiftUI
import NeuralNotesCore

@MainActor
struct NotebookForm: View {
    let model: LibraryViewModel
    let notebook: Notebook?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var cover: NotebookCover
    @State private var folderID: UUID?
    @State private var formError: String?
    @State private var template = PageTemplate()

    init(model: LibraryViewModel, notebook: Notebook? = nil) {
        self.model = model
        self.notebook = notebook
        _title = State(initialValue: notebook?.title ?? "")
        _cover = State(initialValue: notebook?.cover ?? NotebookCover.allCases[model.notebooks.count % NotebookCover.allCases.count])
        _folderID = State(initialValue: notebook?.folderID ?? model.currentFolderID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quaderno") {
                    TextField("Nome del quaderno", text: $title)
                        .accessibilityIdentifier("notebookNameField")
                        .onSubmit { save() }
                    Picker("Cartella", selection: $folderID) {
                        Text("Nessuna cartella").tag(nil as UUID?)
                        ForEach(model.folderRows, id: \.folder.id) { row in
                            Text(String(repeating: "— ", count: row.depth) + row.folder.title)
                                .tag(Optional(row.folder.id))
                        }
                    }
                }
                Section("Copertina") {
                    Picker("Colore", selection: $cover) {
                        ForEach(NotebookCover.allCases, id: \.self) { value in
                            Label(value.title, systemImage: "book.closed.fill")
                                .foregroundStyle(value.color).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                }
                if notebook == nil { PageTemplateControls(template: $template) }
                if let formError { Section { Text(formError).foregroundStyle(.red) } }
            }
            .navigationTitle(notebook == nil ? "Nuovo quaderno" : "Modifica quaderno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save).fontWeight(.semibold)
                        .disabled((try? LibraryName.validated(title)) == nil)
                        .accessibilityIdentifier("saveNotebookButton")
                }
            }
        }
        .interactiveDismissDisabled(!title.isEmpty)
    }

    private func save() {
        guard (try? LibraryName.validated(title)) != nil else {
            formError = LibraryFailure.invalidName.localizedDescription
            return
        }
        let succeeded: Bool
        if let notebook {
            succeeded = model.update(notebook, title: title, cover: cover, folderID: folderID)
        } else {
            succeeded = model.create(title: title, cover: cover, folderID: folderID, template: template)
        }
        if succeeded { dismiss() }
        else { formError = model.errorMessage; model.errorMessage = nil }
    }
}
