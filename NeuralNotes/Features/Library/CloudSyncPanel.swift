import SwiftUI
import NeuralNotesCore

@MainActor
struct CloudSyncPanel: View {
    let library: LibraryViewModel
    @Bindable private var sync = CloudNotebookSync.shared
    @Bindable private var cloud = CloudBackupService.shared
    @AppStorage("cloud.automatic") private var automatic = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                accountBackup
                if !cloud.queue.jobs.isEmpty { pendingBackups }
                if !cloud.documents.isEmpty { cloudCopies }
                Section("iCloud privato") {
                    Toggle("Sincronizza i quaderni chiusi mentre l’app è aperta", isOn: $automatic)
                    Text("Le modifiche offline restano sul dispositivo. I quaderni aperti si sincronizzano dopo la chiusura. Le eliminazioni restano nel cestino locale: non cancellano le copie iCloud.").font(.caption)
                    Button(sync.busy ? "Sincronizzazione…" : "Sincronizza adesso", systemImage: "icloud") { Task { await sync.synchronize(library) } }.disabled(sync.busy)
                    Text(sync.status).font(.callout).textSelection(.enabled)
                }
                Section("Conflitti · \(sync.conflicts.count)") {
                    ForEach(sync.conflicts.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(library.notebooks.first(where: { $0.documentID == id })?.title ?? "Quaderno").font(.headline)
                            Text("Locale e iCloud sono cambiati entrambi. Nessuna versione è stata sostituita.").font(.caption)
                            Button("Importa anche la copia remota") { Task { await sync.importConflictCopy(id, library: library) } }
                            Button("Mantieni la versione locale") { Task { await sync.resolve(id, keepingLocal: true, library: library) } }
                            Button("Usa la versione iCloud · salva prima un backup locale") { Task { await sync.resolve(id, keepingLocal: false, library: library) } }
                        }
                    }
                }.disabled(sync.busy)
            }.navigationTitle("Cloud e sincronizzazione")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private var accountBackup: some View {
        Section("Backup nel cloud NeuralNotes") {
            Text("Copie dei quaderni chiusi nel tuo account NeuralNotes, fino a 100 MB ciascuna. Ogni salvataggio conserva sul server anche le versioni precedenti; scaricare crea sempre un nuovo quaderno, senza sostituire quelli locali.").font(.caption)
            Button(cloud.busy ? "Backup in corso…" : "Salva tutti i quaderni chiusi", systemImage: "icloud.and.arrow.up") { Task { await cloud.backupAll(library) } }.disabled(cloud.busy)
            Menu {
                ForEach(library.notebooks) { book in
                    Button(book.title) { Task { await cloud.backup(book, library: library) } }
                }
            } label: { Label("Salva un quaderno…", systemImage: "square.and.arrow.up.on.square") }.disabled(cloud.busy || library.notebooks.isEmpty)
            Button("Mostra le copie nel cloud", systemImage: "arrow.clockwise.icloud") { Task { await cloud.refresh() } }.disabled(cloud.busy)
            if cloud.busy { ProgressView() }
            if !cloud.status.isEmpty { Text(cloud.status).font(.callout).textSelection(.enabled) }
            Text("Serve l’accesso all’account NeuralNotes (Lente AI → Connessione AI → Account).").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pendingBackups: some View {
        Section("In attesa · \(cloud.queue.jobs.count)") {
            ForEach(cloud.queue.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title).font(.headline)
                    Text("\(ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file)) · \(stage(job))").font(.caption).foregroundStyle(.secondary)
                    if let error = job.lastError { Text(error).font(.caption).foregroundStyle(job.conflict ? Color.orange : Color.red) }
                    if job.conflict {
                        Button("Sostituisci la versione del cloud con questa") { Task { await cloud.replaceCloudVersion(job.documentID) } }
                        if let remote = cloud.documents.first(where: { $0.id == job.documentID }) {
                            Button("Scarica la versione del cloud come copia") { Task { await cloud.downloadCopy(remote, library: library) } }
                        }
                    }
                    Button("Annulla questo backup", role: .destructive) { Task { await cloud.discard(job.documentID) } }
                }
            }
            Button("Riprova adesso", systemImage: "arrow.triangle.2.circlepath") { Task { await cloud.retry() } }
        }.disabled(cloud.busy)
    }

    private var cloudCopies: some View {
        Section("Copie nel cloud · \(cloud.documents.count)") {
            ForEach(cloud.documents) { document in
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title.isEmpty ? "Quaderno" : document.title).font(.headline)
                    Text("Versione \(document.revision) · \(ByteCountFormatter.string(fromByteCount: document.bytes, countStyle: .file))"
                         + (document.updatedAt.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")).font(.caption).foregroundStyle(.secondary)
                    Button("Scarica come nuovo quaderno", systemImage: "icloud.and.arrow.down") { Task { await cloud.downloadCopy(document, library: library) } }
                }
            }
        }.disabled(cloud.busy)
    }

    private func stage(_ job: CloudBackupJob) -> String {
        if job.conflict { return "versione più recente nel cloud" }
        switch job.stage {
        case .prepared: return "da caricare"
        case .reserved: return "caricamento da riprendere"
        case .uploaded: return "caricato, da confermare"
        }
    }
}
