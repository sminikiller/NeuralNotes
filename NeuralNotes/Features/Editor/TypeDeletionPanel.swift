import SwiftUI
import NeuralNotesCore

@MainActor
struct TypeDeletionPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    private enum Scope: String, CaseIterable { case current = "Questa pagina", selected = "Selezionate", notebook = "Quaderno" }
    private struct Request: Hashable { let scope: Scope; let ids: Set<UUID>; let refresh: Int }
    @State private var scope: Scope
    @State private var selectedPages: Set<UUID>
    @State private var kinds = Set<PageDeletionKind>()
    @State private var preview: TypeDeletionPreview?
    @State private var counting = false
    @State private var applying = false
    @State private var confirming = false
    @State private var progress = ""
    @State private var error: String?
    @State private var refresh = 0
    init(model: EditorViewModel, pages: Set<UUID>? = nil, wholeNotebook: Bool = false) {
        self.model = model
        _scope = State(initialValue: wholeNotebook ? .notebook : pages == nil ? .current : .selected)
        _selectedPages = State(initialValue: pages ?? [])
    }
    private var ids: Set<UUID> {
        switch scope {
        case .current: return Set([model.page?.id].compactMap { $0 })
        case .selected: return selectedPages
        case .notebook: return Set(model.pages.map(\.id))
        }
    }
    private var request: Request { Request(scope: scope, ids: ids, refresh: refresh) }
    private var total: Int { preview?.count(kinds) ?? 0 }
    var body: some View {
        NavigationStack {
            List {
                Section("Ambito") {
                    Picker("Pagine", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(applying)
                    Text("\(ids.count) pagine").font(.caption).foregroundStyle(.secondary)
                    if preview?.requiresBackup == true { Text("Prima della modifica viene creato un backup del quaderno.").font(.caption) }
                }
                Section("Elementi da eliminare") {
                    ForEach(PageDeletionKind.allCases) { kind in
                        Toggle(isOn: Binding(get: { kinds.contains(kind) }, set: { if $0 { kinds.insert(kind) } else { kinds.remove(kind) } })) {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                Text(counting ? "…" : "\(preview?.counts[kind, default: 0] ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }.disabled(applying).accessibilityIdentifier("deleteType-\(kind.rawValue)")
                    }
                    Text("Collegamenti audio rimuove i rimandi ai punti di ascolto. Gli oggetti bloccati sono esclusi dal conteggio.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if counting || applying { ProgressView(progress).accessibilityIdentifier("typeDeletionProgress") }
                    Button("Elimina \(total) elementi", role: .destructive) { confirming = true }
                        .disabled(counting || applying || preview == nil || total == 0 || model.audio?.recording == true || model.audio?.compressionTask != nil)
                        .accessibilityIdentifier("typeDeletionApply")
                    if model.audio?.recording == true || model.audio?.compressionTask != nil { Text("Concludi la registrazione o la compressione per procedere.").font(.caption) }
                    Button("Ricalcola conteggi", systemImage: "arrow.clockwise") { refresh += 1 }.disabled(counting || applying)
                    Text("Una sola azione Annulla ripristina gli elementi su tutte le pagine coinvolte.").font(.caption).foregroundStyle(.secondary)
                }
                if scope == .selected { pageChoices }
            }
            .accessibilityIdentifier("typeDeletionList")
            .navigationTitle("Elimina elementi per tipo")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() }.disabled(applying) } }
            .interactiveDismissDisabled(applying)
            .task(id: request) { await calculate() }
            .confirmationDialog("Eliminare \(total) elementi in \(preview?.pageIDs.count ?? 0) pagine?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Elimina elementi", role: .destructive) { apply() }.accessibilityIdentifier("typeDeletionConfirm")
            }
            .alert("Eliminazione non completata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Ricalcola") { error = nil; refresh += 1 }
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private var pageChoices: some View {
        Section("Scegli le pagine") {
            Button("Seleziona tutte") { selectedPages = Set(model.pages.map(\.id)) }.disabled(applying)
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { row in
                Toggle(row.element.title.map { "\(row.offset + 1) · \($0)" } ?? "Pagina \(row.offset + 1)", isOn: Binding(
                    get: { selectedPages.contains(row.element.id) }, set: { if $0 { selectedPages.insert(row.element.id) } else { selectedPages.remove(row.element.id) } }))
                    .disabled(applying)
            }
        }
    }
    private func calculate() async {
        let requested = request
        preview = nil
        guard !requested.ids.isEmpty, !applying else { counting = false; return }
        counting = true; progress = "Conteggio degli elementi…"
        do {
            let result = try await model.typeDeletionPreview(pageIDs: requested.ids, wholeNotebook: requested.scope == .notebook) { done, total in
                guard request == requested else { return }; progress = "Conteggio \(done)/\(total)"
            }
            guard !Task.isCancelled, request == requested else { return }
            preview = result; counting = false
        } catch is CancellationError { if request == requested { counting = false } }
        catch { if !Task.isCancelled, request == requested { self.error = error.localizedDescription; counting = false } }
    }
    private func apply() {
        guard let preview, !applying else { return }; applying = true
        Task {
            do {
                _ = try await model.deleteTypes(kinds, preview: preview) { progress = $0 }
                applying = false; dismiss()
            } catch { applying = false; self.error = error.localizedDescription }
        }
    }
}
