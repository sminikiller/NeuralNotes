import SwiftUI
import NeuralNotesCore

@MainActor
struct LayerExportPanel: View {
    @Bindable var model: EditorViewModel
    var only: UUID? = nil
    private enum Format: String, CaseIterable { case pdf = "PDF vettoriale", png = "PNG", jpeg = "JPEG" }
    private enum Contents: String, CaseIterable { case visible = "Visibili", all = "Tutti", selected = "Scegli" }
    private struct Shared: Identifiable { let id = UUID(); let url: URL }
    @Environment(\.dismiss) private var dismiss
    @State private var format = Format.pdf
    @State private var contents = Contents.visible
    @State private var chosen = Set<UUID>()
    @State private var notebook = false
    @State private var working = false
    @State private var failure: String?
    @State private var shared: Shared?
    private var layers: [PageLayer] { model.page.map { Array(PageLayers.ordered(in: $0).reversed()) } ?? [] }
    private var selection: LayerExportSelection {
        if let only { return .selected([only]) }
        switch contents { case .visible: return .visible; case .all: return .all; case .selected: return .selected(chosen) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Formato") {
                    Picker("File", selection: $format) { ForEach(Format.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if format == .pdf, only == nil, contents != .selected { Toggle("Tutto il quaderno", isOn: $notebook) }
                }
                Section("Livelli") {
                    if let only {
                        Label(layers.first(where: { $0.id == only })?.name ?? "Livello", systemImage: "square.3.layers.3d")
                        Text("Esporta questo livello della pagina, anche se nascosto. Gli originali rimangono nel quaderno.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Contenuto", selection: $contents) { ForEach(Contents.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        if contents == .selected {
                            ForEach(layers) { layer in
                                Toggle(layer.name, isOn: Binding(get: { chosen.contains(layer.id) }, set: { value in
                                    if value { chosen.insert(layer.id) } else { chosen.remove(layer.id) }
                                }))
                            }
                            Text("La scelta dei livelli riguarda questa pagina.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Il PDF e la carta restano lo sfondo. L’esportazione non modifica visibilità, opacità o blocchi del quaderno.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if working { ProgressView("Preparazione del file…") }
                    Button("Prepara e condividi", systemImage: "square.and.arrow.up") { Task { await prepare() } }
                        .disabled(working || (only == nil && contents == .selected && chosen.isEmpty))
                        .accessibilityIdentifier("layerExportApply")
                    if let failure { Text(failure).foregroundStyle(.red) }
                }
            }.disabled(working)
                .navigationTitle("Esporta livelli")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() }.disabled(working) } }
                .interactiveDismissDisabled(working)
                .sheet(item: $shared) { ShareDocument(url: $0.url) }
        }
    }
    private func prepare() async {
        working = true; failure = nil; defer { working = false }
        guard let pageID = model.page?.id, await model.flush(), model.page?.id == pageID else { return }
        do {
            let output: URL
            switch format {
            case .pdf:
                let whole = notebook && only == nil && contents != .selected
                output = try await DocumentServices.exportPDF(workspace: model.workspace, layers: selection,
                    pageIDs: whole ? nil : [pageID])
            case .png: output = try await model.exportPageImage(layers: selection)
            case .jpeg: output = try await model.exportPageImage(jpeg: true, layers: selection)
            }
            try Task.checkCancellation(); shared = Shared(url: output)
        } catch { failure = error.localizedDescription }
    }
}
