import SwiftUI
import NeuralNotesCore
import UniformTypeIdentifiers

@MainActor
struct RecoveryPanel: View {
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [URL] = []
    @State private var error: String?
    @State private var busy = false
    @State private var damaged: [Notebook] = []
    @State private var pending: Notebook?
    @State private var catalogs: [CatalogRecoveryItem] = []
    @State private var pendingCatalog: Notebook?
    @State private var choosingFolder = false
    @State private var folderResult: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Un’interruzione può lasciare un quaderno completo non ancora aggiunto alla libreria. Recuperalo qui: i file originali non vengono spostati o cancellati.").font(.callout)
                    Text("Copie diverse di Swift Playground possono avere dati separati. Questa app non può accedere automaticamente al contenitore di un’altra copia. Puoi importare backup o scegliere da File una cartella Notebooks conservata.").font(.caption).foregroundStyle(.secondary)
                    Button("Importa quaderni da una cartella", systemImage: "folder.badge.plus") { choosingFolder = true }
                    if let folderResult { Text(folderResult).font(.caption) }
                }
                ForEach(packages, id: \.path) { url in
                    Button {
                        Task {
                            busy = true; defer { busy = false }
                            do { try await library.recover(url); await refresh() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: { Label("Recupera \(url.deletingPathExtension().lastPathComponent.prefix(8))", systemImage: "arrow.uturn.backward.circle") }
                }
                if !damaged.isEmpty {
                    Section("Indice da recuperare") {
                        ForEach(damaged) { notebook in
                            Button("Ripristina indice precedente · \(notebook.title)", systemImage: "clock.arrow.circlepath") { pending = notebook }
                        }
                    }
                }
                if !catalogs.isEmpty {
                    Section("Audio, trascrizioni e configurazioni da recuperare") {
                        ForEach(catalogs) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Button("Ripristina catalogo precedente · \(item.notebook.title)", systemImage: "clock.arrow.circlepath") { pendingCatalog = item.notebook }
                                    .disabled(!item.canRestore || EditorLeases.shared.isOpen(item.notebook.documentID))
                                if !item.canRestore { Text("Nessuna copia leggibile disponibile. Conserva i file e usa un backup del quaderno.").font(.caption) }
                                else if EditorLeases.shared.isOpen(item.notebook.documentID) { Text("Chiudi prima il quaderno nell’editor.").font(.caption) }
                            }
                        }
                    }
                }
                if packages.isEmpty && damaged.isEmpty && catalogs.isEmpty { Label("Nessun quaderno da recuperare", systemImage: "checkmark.shield") }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy)
            .navigationTitle("Recupero quaderni")
            .task { await refresh() }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                Task {
                    busy = true; defer { busy = false }
                    do {
                        let report = try await library.importRecoveryFolder(result.get())
                        folderResult = "\(report.imported) quaderni importati come copie. Gli originali sono conservati."
                        error = report.failures.isEmpty ? nil : report.failures.prefix(5).joined(separator: "\n")
                        if report.imported == 0 && report.failures.isEmpty { folderResult = "Nessuna cartella quaderno con manifest.json trovata nelle prime quattro sottocartelle." }
                        await refresh()
                    } catch { self.error = error.localizedDescription }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .confirmationDialog("Ripristinare l’indice precedente?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Ripristina indice") {
                    Task {
                        busy = true; defer { busy = false; pending = nil }
                        do { if let pending { try library.repair(pending) }; await refresh() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("L’ordine delle pagine tornerà all’ultima versione disponibile. Il file attuale verrà conservato per il recupero; nessun vettore o media viene eliminato.") }
            .confirmationDialog("Ripristinare il catalogo precedente?", isPresented: Binding(get: { pendingCatalog != nil }, set: { if !$0 { pendingCatalog = nil } }), titleVisibility: .visible) {
                Button("Ripristina catalogo") {
                    Task {
                        busy = true; defer { busy = false; pendingCatalog = nil }
                        do { if let pendingCatalog { try await library.repairCatalog(pendingCatalog) }; await refresh() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("Audio, trascrizioni e configurazioni torneranno alla copia precedente. Il catalogo attuale e tutti i media presenti saranno conservati; l’inchiostro delle pagine non cambia.") }
        }
    }
    private func refresh() async {
        do { packages = try library.recoverablePackages(); damaged = library.damagedNotebooks(); catalogs = await library.catalogRecoveryItems() }
        catch { self.error = error.localizedDescription }
    }
}
