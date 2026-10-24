import SwiftUI
import NeuralNotesCore

@MainActor
struct CloudVersionsPanel: View {
    let document: CloudDocument
    let library: LibraryViewModel
    @Bindable private var cloud = CloudBackupService.shared
    @State private var versions: [CloudSnapshot] = []
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Scaricare crea una copia indipendente. Il quaderno attuale e le versioni sul server restano conservati.").font(.callout) }
                if loading { ProgressView("Caricamento versioni…") }
                ForEach(versions) { version in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Versione \(version.revision)").font(.headline)
                        Text(version.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Data non disponibile").font(.caption)
                        Text(ByteCountFormatter.string(fromByteCount: version.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        Button("Scarica questa versione come copia", systemImage: "icloud.and.arrow.down") {
                            Task { await cloud.downloadVersion(version, title: document.title, library: library) }
                        }.disabled(cloud.busy)
                    }.padding(.vertical, 4)
                }
                if !loading, versions.isEmpty { Text("Nessuna versione disponibile.") }
                if !cloud.status.isEmpty { Text(cloud.status).font(.caption).textSelection(.enabled) }
            }.navigationTitle("Versioni · \(document.title)")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }.task { versions = await cloud.versions(document); loading = false }
    }
}
