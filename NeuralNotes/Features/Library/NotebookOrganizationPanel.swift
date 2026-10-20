import SwiftUI
import NeuralNotesCore

@MainActor
struct NotebookOrganizationPanel: View {
    let library: LibraryViewModel
    let notebook: Notebook
    @Environment(\.dismiss) private var dismiss
    @State private var value = NotebookOrganization()
    @State private var tags = ""
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section(notebook.title) {
                    Toggle("In primo piano", isOn: $value.pinned)
                    Toggle("Da organizzare nell’Inbox", isOn: $value.inbox)
                    TextField("Tag separati da virgole", text: $tags, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Fino a 20 tag, 32 caratteri ciascuno. I tag vengono salvati nel quaderno e inclusi nei backup.").font(.caption)
                }
            }.navigationTitle("Organizza")
                .task {
                    value = (try? await library.workspace(notebook).catalog().organization) ?? NotebookOrganization()
                    tags = value.tags.joined(separator: ", ")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") {
                        busy = true; value.tags = NotebookOrganization.tags(from: tags)
                        Task { if await library.setOrganization(value, for: notebook) { dismiss() }; busy = false }
                    }.disabled(busy || !validTags) }
                }
        }
    }
    private var validTags: Bool { var draft = value; draft.tags = NotebookOrganization.tags(from: tags); return draft.isValid }
}
