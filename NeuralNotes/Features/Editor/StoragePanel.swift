import SwiftUI
import NeuralNotesCore

@MainActor
struct StoragePanel: View {
    let workspace: DocumentWorkspace
    var editor: EditorViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var report: WorkspaceStorageReport?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmation = false
    @State private var deletePages = false
    private var canClean: Bool { !EditorLeases.shared.isOpen(workspace.documentID) }
    private var canRestore: Bool { canClean || editor?.hasLease == true }

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section("Spazio occupato") {
                        LabeledContent("Totale", value: bytes(report.totalBytes))
                        LabeledContent("File non referenziati", value: bytes(report.unusedBytes))
                        ForEach(report.categoryBytes.keys.sorted(), id: \.self) { key in
                            LabeledContent(category(key), value: bytes(report.categoryBytes[key] ?? 0))
                        }
                    }
                    if !report.unreadableHeaders.isEmpty {
                        Section("Contenuti da verificare") {
                            Text("Pulizia disattivata: alcuni indici non sono leggibili. I file restano conservati.").foregroundStyle(.orange)
                            ForEach(report.unreadableHeaders, id: \.self) { Text($0).font(.caption) }
                        }
                    }
                    Section("Pagine rimosse recuperabili · \(report.removedPages.count)") {
                        ForEach(report.removedPages) { page in
                            Button { Task { await restore(page) } } label: {
                                Label(page.title ?? "Pagina \(page.id.uuidString.prefix(8))", systemImage: "arrow.uturn.backward")
                            }.disabled(!canRestore)
                        }
                        if report.removedPages.isEmpty { Text("Nessuna pagina rimossa.").foregroundStyle(.secondary) }
                    }
                    Section("Pulizia") {
                        if !canClean { Text("Chiudi il quaderno nelle finestre prima di pulire lo spazio. Puoi recuperare le pagine anche dall’editor.").font(.caption) }
                        Button("Libera file non referenziati", systemImage: "sparkles") { deletePages = false; confirmation = true }
                            .disabled(!canClean || report.unusedFiles.isEmpty || !report.unreadableHeaders.isEmpty)
                        Button("Elimina definitivamente le pagine rimosse", systemImage: "trash", role: .destructive) { deletePages = true; confirmation = true }
                            .disabled(!canClean || report.removedPages.isEmpty || !report.unreadableHeaders.isEmpty)
                    }
                } else { ProgressView("Analisi del quaderno…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .disabled(busy)
            .navigationTitle("Spazio e recupero")
            .task { if let editor { _ = await editor.flush() }; await refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Aggiorna", systemImage: "arrow.clockwise") { Task { await refresh() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
            }
            .confirmationDialog(deletePages ? "Eliminare definitivamente le pagine rimosse?" : "Eliminare i file non referenziati?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Elimina definitivamente", role: .destructive) { Task { await clean() } }
            } message: { Text(deletePages ? "Le pagine rimosse non saranno più recuperabili. I loro media potranno essere rimossi con la pulizia successiva." : "Pagine attive, pagine recuperabili e rispettive revisioni rimangono protette.") }
        }
    }
    private func refresh() async {
        do { report = try await workspace.storageReport() } catch { self.error = error.localizedDescription }
    }
    private func clean() async {
        guard canClean else { return }
        busy = true; defer { busy = false }
        do {
            if deletePages { try await workspace.permanentlyRemovePages(report?.removedPages.map(\.id) ?? []) }
            else { _ = try await workspace.cleanUnusedFiles() }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func restore(_ page: PageSnapshot) async {
        guard canRestore else { return }
        busy = true; defer { busy = false }
        do {
            let order = try await workspace.manifest().pageIDs
            try await workspace.restoreRemovedPage(page.id)
            if let editor {
                editor.pages = try await workspace.pages()
                editor.recordOrder(order, selectedBefore: editor.page?.id, label: "Recupera pagina")
            }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func category(_ key: String) -> String {
        ["audio": "Audio", "images": "Immagini", "attachments": "PDF e allegati", "drawings": "Inchiostro", "pages": "Pagine", "artifacts": "Studio"][key] ?? "Metadati"
    }
}
