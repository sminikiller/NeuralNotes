import SwiftUI

@MainActor
struct CloudSyncPanel: View {
    let library: LibraryViewModel
    @Bindable private var sync = CloudNotebookSync.shared
    @AppStorage("cloud.automatic") private var automatic = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
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
            }.navigationTitle("Sincronizzazione iCloud")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
