import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NeuralNotesCore

@MainActor
struct ICloudSyncPanel: View {
    let library: LibraryViewModel
    @Bindable private var sync = CloudNotebookSync.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var exporting = false
    @State private var importing = false
    @State private var choosingFolder = false
    @AppStorage("backup.external.name") private var backupFolder: String?
    @State private var workingWithFiles = false
    @State private var archive: URL?
    @State private var fileStatus: String?

    var body: some View {
        Form {
            appleAccount
            if CloudNotebookSync.isSupported { synchronization }
            fileBackups
            if !sync.conflicts.isEmpty { conflicts }
        }
        .navigationTitle("Account Apple e iCloud")
        .task(id: scenePhase) { if scenePhase == .active { await sync.refreshConnection() } }
        .sheet(isPresented: $exporting, onDismiss: clearExport) {
            if let archive {
                NotebookBackupPicker(file: archive) { saved in
                    if saved { fileStatus = "Copia del quaderno salvata nella posizione scelta in File." }
                    exporting = false
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: choosingFolder ? [.folder] : [.data]) { result in
            if choosingFolder {
                do { try ExternalBackupDestination.choose(result.get()); fileStatus = "Destinazione per le copie automatiche aggiornata." }
                catch { fileStatus = error.localizedDescription }
            } else {
                Task { await restore(result) }
            }
        }
    }

    private var appleAccount: some View {
        Section("Account Apple") {
            Label(sync.status, systemImage: sync.connected ? "person.crop.circle.badge.checkmark" : "icloud")
                .accessibilityIdentifier("iCloudConnectionStatus")
            Text("Per iCloud usa Impostazioni → Account Apple → iCloud. L’accesso all’Account NeuralNotes per l’AI e il cloud NeuralNotes si gestisce in Account e servizi.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Apri Impostazioni", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            if CloudNotebookSync.isSupported {
                Button("Verifica la connessione", systemImage: "arrow.clockwise") { Task { await sync.refreshConnection() } }
                    .disabled(sync.busy)
            }
        }
    }

    private var synchronization: some View {
        Section("Sincronizzazione privata") {
            Toggle("Sincronizza automaticamente tutti i quaderni chiusi", isOn: Binding(
                get: { sync.automatic }, set: { enabled in Task { await sync.setAutomatic(enabled, library: library) } }
            )).disabled(sync.busy || !sync.connected)
            Button("Sincronizza tutti i quaderni chiusi", systemImage: "arrow.triangle.2.circlepath.icloud") {
                Task { await sync.synchronize(library) }
            }.disabled(sync.busy || !sync.connected)
            Menu {
                ForEach(library.notebooks) { book in
                    Button(book.title) { Task { await sync.synchronize(library, documentID: book.documentID) } }
                }
            } label: { Label("Sincronizza un quaderno…", systemImage: "icloud.and.arrow.up") }
                .disabled(sync.busy || !sync.connected || library.notebooks.isEmpty)
            if let date = sync.lastSyncAt {
                LabeledContent("Ultimo controllo", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if sync.busy { ProgressView() }
            Text("Sul secondo iPad usa lo stesso Account Apple e sincronizza per ricevere i quaderni. La sincronizzazione automatica avviene mentre NeuralNotes è attiva, anche dopo la chiusura del quaderno. Cartelle e cestino restano locali.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fileBackups: some View {
        Section("Backup in File") {
            Menu {
                ForEach(library.notebooks) { book in
                    Button(book.title) { Task { await export(book) } }
                }
            } label: { Label("Salva la copia di un quaderno…", systemImage: "square.and.arrow.up") }
                .disabled(workingWithFiles || library.notebooks.isEmpty)
                .accessibilityIdentifier("iCloudSaveNotebook")
            Button("Ripristina una copia da File", systemImage: "square.and.arrow.down") {
                choosingFolder = false; importing = true
            }
                .disabled(workingWithFiles)
                .accessibilityIdentifier("iCloudRestoreNotebook")
            Text("Chiudi il quaderno per creare una copia con pagine, foto, PDF, audio e trascrizioni. Scegli iCloud Drive oppure un’altra posizione in File. Il ripristino di un backup nativo aggiunge una copia indipendente alla libreria.")
                .font(.caption).foregroundStyle(.secondary)
            if let backupFolder { LabeledContent("Cartella per le copie automatiche", value: backupFolder) }
            Button("Scegli la cartella per le copie automatiche", systemImage: "folder.badge.plus") {
                choosingFolder = true; importing = true
            }.disabled(workingWithFiles)
            Text("Scegli una cartella di iCloud Drive per ricevere le copie future create con Backup automatici attivo in Spazio e recupero.")
                .font(.caption).foregroundStyle(.secondary)
            if workingWithFiles { ProgressView() }
            if let fileStatus { Text(fileStatus).font(.callout).textSelection(.enabled) }
        }
    }

    private var conflicts: some View {
        Section("Conflitti · \(sync.conflicts.count)") {
            ForEach(sync.conflicts.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                    Text(library.notebooks.first(where: { $0.documentID == id })?.title ?? "Quaderno").font(.headline)
                    Text("Il quaderno è cambiato sia qui sia su iCloud. Puoi importare la copia remota per confrontarle.").font(.caption)
                    Button("Importa la copia remota") { Task { await sync.importConflictCopy(id, library: library) } }
                    Button("Mantieni la versione locale") { Task { await sync.resolve(id, keepingLocal: true, library: library) } }
                    Button("Usa la versione iCloud dopo il backup locale") { Task { await sync.resolve(id, keepingLocal: false, library: library) } }
                }.buttonStyle(.borderless)
            }
        }.disabled(sync.busy)
    }

    private func export(_ book: Notebook) async {
        guard !workingWithFiles else { return }
        guard EditorLeases.shared.reserveCloud(book.documentID) else {
            fileStatus = "Chiudi il quaderno e attendi la fine del salvataggio prima di esportarlo."
            return
        }
        workingWithFiles = true
        fileStatus = nil
        defer { workingWithFiles = false; EditorLeases.shared.releaseCloud(book.documentID) }
        do {
            archive = try await library.workspace(book).exportNative(metadata: book)
            exporting = true
        } catch { fileStatus = error.localizedDescription }
    }

    private func clearExport() {
        if let archive { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        archive = nil
    }

    private func restore(_ result: Result<URL, Error>) async {
        guard !library.importing else { fileStatus = "Un’importazione è già in corso."; return }
        workingWithFiles = true
        defer { workingWithFiles = false }
        do {
            let url = try result.get()
            guard url.pathExtension.lowercased() == "nnbackup" else {
                fileStatus = "Seleziona un backup NeuralNotes con estensione .nnbackup."
                return
            }
            try await library.restoreNativeBackup(from: url)
            fileStatus = "Copia importata nella libreria."
        } catch { fileStatus = error.localizedDescription }
    }
}

private struct NotebookBackupPicker: UIViewControllerRepresentable {
    let file: URL
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void
        init(finished: @escaping (Bool) -> Void) { self.finished = finished }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finished(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished(false) }
    }
}
