import SwiftUI
import NeuralNotesCore

@MainActor
struct PageTrashPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [PageSnapshot] = []
    @State private var selection = Set<UUID>()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Il pulsante Ripristina riporta le pagine nel quaderno. Le pagine restano qui finché non le elimini definitivamente da Spazio e recupero. Le pagine selezionate verranno aggiunte in fondo al quaderno.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(pages) { page in
                    Button {
                        if selection.contains(page.id) { selection.remove(page.id) } else { selection.insert(page.id) }
                    } label: {
                        HStack {
                            Image(systemName: selection.contains(page.id) ? "checkmark.circle.fill" : "circle")
                            PageThumbnail(page: page, workspace: model.workspace).frame(width: 48, height: 64)
                            Text(page.title ?? "Pagina rimossa").foregroundStyle(.primary)
                        }
                    }.accessibilityIdentifier("trashedPage-\(page.id)")
                }
                if pages.isEmpty { ContentUnavailableView("Cestino vuoto", systemImage: "trash") }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle("Cestino pagine")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Tutte") { selection = Set(pages.map(\.id)) }.disabled(pages.isEmpty) }
                    ToolbarItem(placement: .bottomBar) { Button("Ripristina \(selection.count) pagine nel quaderno", systemImage: "arrow.uturn.backward") { restore() }.labelStyle(.titleAndIcon).accessibilityIdentifier("restoreTrashedPages").disabled(selection.isEmpty) }
                }
                .task { await refresh() }
        }
    }
    private func refresh() async {
        do { pages = try await model.workspace.storageReport().removedPages; selection.formIntersection(Set(pages.map(\.id))) }
        catch { self.error = error.localizedDescription }
    }
    private func restore() {
        let ids = pages.filter { selection.contains($0.id) }.map(\.id)
        Task {
            busy = true; defer { busy = false }
            await model.restorePages(ids); error = model.error
            await refresh()
        }
    }
}
