import SwiftUI
import NeuralNotesCore

@MainActor
struct FolderForm: View {
    let model: LibraryViewModel
    let folder: LibraryFolder?
    let parentID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var formError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome della cartella", text: $title)
                    .accessibilityIdentifier("folderNameField")
                if let formError { Text(formError).foregroundStyle(.red) }
            }
            .navigationTitle(folder == nil ? "Nuova cartella" : "Rinomina cartella")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { title = folder?.title ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let success = folder.map { model.renameFolder($0, title: title) }
                            ?? model.createFolder(title: title, parentID: parentID)
                        if success { dismiss() }
                        else { formError = model.errorMessage; model.errorMessage = nil }
                    }
                    .disabled((try? LibraryName.validated(title)) == nil)
                }
            }
        }
    }
}
