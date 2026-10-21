import SwiftUI
import UniformTypeIdentifiers
import NeuralNotesCore

@MainActor
struct StoragePanel: View {
    let workspace: DocumentWorkspace
    var editor: EditorViewModel? = nil
    var metadata: Notebook? = nil
    @AppStorage("backup.automatic") private var automaticBackup = true
    @State private var choosingBackupFolder = false
    @State private var externalFolderName = ExternalBackupDestination.name
    @State private var backups: [AutomaticBackupInfo] = []
    @State private var backupUsage: AutomaticBackupUsage?
    @State private var compressionEstimate: AudioCompressionEstimate?
    @Environment(\.dismiss) private var dismiss
    @State private var report: WorkspaceStorageReport?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmation = false
    @State private var deletePages = false
    @State private var catalogRecovery: CatalogRecoveryStatus?
    @State private var confirmCatalogRecovery = false
    private var canClean: Bool { !EditorLeases.shared.isOpen(workspace.documentID) }
    private var canRestore: Bool { canClean || editor?.hasLease == true }

    var body: some View {
        NavigationStack {
            List {
                Section("Audio") {
                    NavigationLink { AudioCompressionPanel(workspace: workspace, editor: editor) } label: {
                        Label("Comprimi registrazioni", systemImage: "waveform")
                    }
                    if let compressionEstimate {
                        LabeledContent("Recuperabili, stima", value: bytes(compressionEstimate.recoverableBytes))
                    }
                }
                Section("Backup automatici") {
                    Toggle("Copie automatiche ogni 10 minuti di modifiche", isOn: $automaticBackup)
                    Text("Fino a cinque versioni entro il minore tra 1 GB e tre volte il quaderno, con un minimo di 64 MB. Le due copie più recenti sono sempre conservate, anche oltre limite. Durante una registrazione il backup attende la pausa.").font(.caption)
                    if let backupUsage {
                        LabeledContent("Spazio backup", value: bytes(backupUsage.usedBytes))
                        LabeledContent("Limite", value: bytes(backupUsage.budgetBytes))
                        if backupUsage.exceedsBudget { Text("Le due copie protette superano il limite: vengono mantenute per il recupero.").font(.caption).foregroundStyle(.orange) }
                    }
                    if let warning = editor?.backupWarning { Text(warning).foregroundStyle(.orange) }
                    if let metadata {
                        Button("Crea copia adesso", systemImage: "externaldrive.badge.plus") {
                            Task {
                                busy = true; defer { busy = false }
                                if let editor, !(await editor.flush()) { return }
                                do {
                                    if let file = try await workspace.createAutomaticBackup(metadata: metadata, minimumInterval: 0) { _ = try await ExternalBackupWriter.shared.copy(file, documentID: workspace.documentID) }
                                    await refresh()
                                }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(busy || editor?.hasActiveStroke == true)
                    }
                    ForEach(backups) { backup in
                        ShareLink(item: backup.url) {
                            Label("\(backup.date.formatted(date: .abbreviated, time: .shortened)) · \(bytes(backup.bytes))", systemImage: "square.and.arrow.up")
                        }
                    }
                    if backups.isEmpty { Text("La prima copia viene creata dopo il salvataggio del quaderno.").font(.caption) }
                }
                Section("Copia in una cartella di File") {
                    Text(externalFolderName.map { "Destinazione per tutti i quaderni: \($0)" } ?? "Nessuna destinazione scelta").font(.caption)
                    Button("Scegli cartella", systemImage: "folder.badge.plus") { choosingBackupFolder = true }
                    if externalFolderName != nil {
                        Button("Copia ultimo backup adesso", systemImage: "externaldrive") { Task { await copyExternalBackup() } }.disabled(backups.isEmpty)
                        Button("Scollega cartella", role: .destructive) { ExternalBackupDestination.remove(); externalFolderName = nil }
                    }
                    Text("La cartella scelta segue il limite di spazio dei backup e conserva sempre le due copie più recenti. Un errore del provider File non elimina le copie locali.").font(.caption)
                }
                if catalogRecovery?.needsRecovery == true, let editor {
                    Section("Catalogo da recuperare") {
                        Text("Puoi recuperare audio, trascrizioni e configurazioni senza chiudere l’editor. Inchiostro e file originali vengono conservati.")
                        Button("Ripristina catalogo precedente", systemImage: "clock.arrow.circlepath") { confirmCatalogRecovery = true }
                            .disabled(catalogRecovery?.canRestore != true || !editor.canRecoverCatalog)
                        if editor.audio?.recording == true { Text("Metti prima in pausa la registrazione.").font(.caption) }
                        if catalogRecovery?.canRestore != true { Text("Nessuna copia leggibile disponibile: conserva il quaderno originale.").font(.caption) }
                    }
                }
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
            .fileImporter(isPresented: $choosingBackupFolder, allowedContentTypes: [.folder]) { result in
                do {
                    let folder = try result.get(); try ExternalBackupDestination.choose(folder)
                    externalFolderName = ExternalBackupDestination.name
                    Task { await copyExternalBackup() }
                } catch { self.error = error.localizedDescription }
            }
            .confirmationDialog(deletePages ? "Eliminare definitivamente le pagine rimosse?" : "Eliminare i file non referenziati?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Elimina definitivamente", role: .destructive) { Task { await clean() } }
            } message: { Text(deletePages ? "Le pagine rimosse non saranno più recuperabili. I loro media potranno essere rimossi con la pulizia successiva." : "Pagine attive, pagine recuperabili e rispettive revisioni rimangono protette.") }
            .confirmationDialog("Ripristinare il catalogo precedente?", isPresented: $confirmCatalogRecovery, titleVisibility: .visible) {
                Button("Ripristina catalogo") {
                    Task {
                        busy = true; defer { busy = false }
                        if let editor, await editor.recoverCatalog() { error = nil }
                        else { error = editor?.error ?? "Recupero non disponibile: attendi la fine delle operazioni." }
                        await refresh()
                    }
                }
            } message: { Text("Il catalogo attuale e tutti i media saranno conservati. L’editor salva prima la pagina e mantiene le sessioni audio ancora presenti in memoria.") }
        }
    }
    private func copyExternalBackup() async {
        guard let file = backups.first?.url else { return }
        busy = true; defer { busy = false }
        do { _ = try await ExternalBackupWriter.shared.copy(file, documentID: workspace.documentID); error = nil }
        catch { self.error = "Copia esterna da riprovare: \(error.localizedDescription). I backup locali restano disponibili." }
    }
    private func refresh() async {
        backups = (try? await workspace.automaticBackups()) ?? []
        backupUsage = try? await workspace.automaticBackupUsage()
        catalogRecovery = try? await workspace.catalogRecoveryStatus()
        compressionEstimate = try? await AudioCompressionEstimate.measure(workspace)
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
