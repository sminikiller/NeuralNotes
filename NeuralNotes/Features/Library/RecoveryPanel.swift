import SwiftUI
import NeuralNotesCore

@MainActor
struct RecoveryPanel: View {
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [URL] = []
    @State private var error: String?
    @State private var busy = false
    @State private var damaged: [Notebook] = []
    @State private var pending: Notebook?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Un’interruzione può lasciare un quaderno completo non ancora aggiunto alla libreria. Recuperalo qui: i file originali non vengono spostati o cancellati.").font(.callout)
                }
                ForEach(packages, id: \.path) { url in
                    Button {
                        Task {
                            busy = true; defer { busy = false }
                            do { try await library.recover(url); try refresh() }
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
                if packages.isEmpty { Label("Nessun quaderno da recuperare", systemImage: "checkmark.shield") }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy)
            .navigationTitle("Recupero quaderni")
            .task { do { try refresh() } catch { self.error = error.localizedDescription } }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .confirmationDialog("Ripristinare l’indice precedente?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Ripristina indice") {
                    do { if let pending { try library.repair(pending) }; try refresh() }
                    catch { self.error = error.localizedDescription }
                    pending = nil
                }
            } message: { Text("L’ordine delle pagine tornerà all’ultima versione disponibile. Il file attuale verrà conservato per il recupero; nessun vettore o media viene eliminato.") }
        }
    }
    private func refresh() throws { packages = try library.recoverablePackages(); damaged = library.damagedNotebooks() }
}
