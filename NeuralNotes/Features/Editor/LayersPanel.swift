import SwiftUI
import NeuralNotesCore

@MainActor
struct LayersPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renameID: UUID?
    @State private var name = ""
    @State private var renaming = false
    @State private var exporting: UUID?
    private var layers: [PageLayer] { model.page.map { Array(PageLayers.ordered(in: $0).reversed()) } ?? [] }
    private var busy: Bool { model.navigating || model.loading || model.hasActiveStroke }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layers) { layer in
                        LayerPanelRow(model: model, layer: layer, rename: { rename(layer) }, export: { exporting = layer.id })
                    }.onMove(perform: reorder)
                } header: {
                    Text("Dall’alto al basso · \(layers.count)/\(PageLayers.maximumCount)")
                } footer: {
                    Text("Scrivi e seleziona soltanto nel livello attivo. Occhio e lucchetto proteggono gli altri contenuti. Ogni modifica si può annullare.")
                }
                Section {
                    Button("Nuovo livello", systemImage: "plus") { operation(.add("Livello \(layers.count + 1)")) }
                        .disabled(layers.count >= PageLayers.maximumCount || busy).accessibilityIdentifier("layerAdd")
                }
            }.accessibilityIdentifier("layersList")
                .navigationTitle("Livelli")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .primaryAction) { EditButton().disabled(busy) }
                }
                .alert("Nome del livello", isPresented: $renaming) {
                    TextField("Nome", text: $name)
                    Button("Salva") { if let id = renameID { operation(.rename(id, name)) } }
                    Button("Annulla", role: .cancel) { }
                }
                .sheet(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } })) {
                    if let exporting { LayerExportPanel(model: model, only: exporting) }
                }
        }
    }
    private func rename(_ layer: PageLayer) { renameID = layer.id; name = layer.name; renaming = true }
    private func operation(_ value: EditorLayerOperation) { Task { _ = await model.performLayerOperation(value) } }
    private func reorder(from offsets: IndexSet, to destination: Int) {
        var display = layers; display.move(fromOffsets: offsets, toOffset: destination)
        operation(.order(display.reversed().map(\.id)))
    }
}

@MainActor
private struct LayerPanelRow: View {
    @Bindable var model: EditorViewModel
    let layer: PageLayer
    let rename: () -> Void
    let export: () -> Void
    @State private var opacity = 1.0
    private var active: Bool { model.drawingLayerID == layer.id }
    private var editable: Bool { model.page.map { PageLayers.editable(layer.id, page: $0) } ?? false }
    private var busy: Bool { model.navigating || model.loading || model.hasActiveStroke }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await model.selectLayer(layer.id) }
                } label: {
                    HStack(spacing: 12) {
                        if let page = model.page { LayerThumbnail(page: page, layer: layer, workspace: model.workspace) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(layer.name).fontWeight(active ? .semibold : .regular).lineLimit(2)
                            if active { Label("Attivo", systemImage: "pencil.tip").font(.caption).foregroundStyle(.teal) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!editable || busy)
                    .accessibilityIdentifier("layerSelect-\(layer.id)")
                Button { operation(.visibility(layer.id, !layer.isVisible)) } label: {
                    Image(systemName: layer.isVisible ? "eye" : "eye.slash").frame(width: 36, height: 44)
                }.accessibilityLabel(layer.isVisible ? "Nascondi \(layer.name)" : "Mostra \(layer.name)")
                Button { operation(.lock(layer.id, !layer.isLocked)) } label: {
                    Image(systemName: layer.isLocked ? "lock.fill" : "lock.open").frame(width: 36, height: 44)
                }.accessibilityLabel(layer.isLocked ? "Sblocca \(layer.name)" : "Blocca \(layer.name)")
                menu
            }.disabled(busy)
            HStack {
                Text("Opacità").font(.caption)
                Slider(value: $opacity, in: 0...1, onEditingChanged: { editing in
                    if !editing, abs(opacity - (layer.opacity ?? 1)) > 0.001 { operation(.opacity(layer.id, opacity)) }
                }).disabled(busy).accessibilityLabel("Opacità \(layer.name)")
                Text("\(Int((opacity * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
        }.padding(.vertical, 5)
            .onAppear { opacity = layer.opacity ?? 1 }
            .onChange(of: layer.opacity) { _, value in opacity = value ?? 1 }
    }
    private var menu: some View {
        Menu {
            Button("Rinomina", systemImage: "pencil", action: rename)
            Button("Duplica", systemImage: "plus.square.on.square") { operation(.duplicate(layer.id, String(layer.name.prefix(54)) + " copia")) }
                .disabled((model.page?.layers?.count ?? 1) >= PageLayers.maximumCount)
            Button("Unisci al livello sotto", systemImage: "square.3.layers.3d.down.right") { operation(.merge(layer.id)) }.disabled(!canMerge)
            Button("Esporta solo questo livello…", systemImage: "square.and.arrow.up", action: export)
            Divider()
            Button("Svuota livello", systemImage: "eraser", role: .destructive) { operation(.clear(layer.id)) }.disabled(layer.isLocked)
            if layer.id != model.page?.id {
                Button("Elimina livello", systemImage: "trash", role: .destructive) { operation(.remove(layer.id)) }.disabled(layer.isLocked)
            }
        } label: { Image(systemName: "ellipsis.circle").frame(width: 36, height: 44) }
            .accessibilityLabel("Azioni \(layer.name)")
    }
    private var canMerge: Bool {
        guard let page = model.page else { return false }
        let order = PageLayers.ordered(in: page)
        guard let index = order.firstIndex(where: { $0.id == layer.id }), index > 0 else { return false }
        return PageLayers.editable(layer.id, page: page) && PageLayers.editable(order[index - 1].id, page: page)
    }
    private func operation(_ value: EditorLayerOperation) { Task { _ = await model.performLayerOperation(value) } }
}

@MainActor
private struct LayerThumbnail: View {
    let page: PageSnapshot, layer: PageLayer, workspace: DocumentWorkspace
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "square.3.layers.3d").foregroundStyle(.secondary) }
        }.frame(width: 48, height: 64).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
            .task(id: "\(page.id)|\(page.revision)|\(layer.id)") {
                let value = await LayerThumbnailPipeline.image(page: page, layerID: layer.id, workspace: workspace)
                if !Task.isCancelled { image = value }
            }
    }
}

/// Rows never hold sixteen decoded native drawings while awaiting each other.
@MainActor
private enum LayerThumbnailPipeline {
    static var tail: Task<UIImage?, Never>?
    static func image(page: PageSnapshot, layerID: UUID, workspace: DocumentWorkspace) async -> UIImage? {
        let previous = tail
        let next = Task { @MainActor () -> UIImage? in
            _ = await previous?.value
            guard !Task.isCancelled else { return nil }
            return try? await DocumentServices.compositeImage(page: page, workspace: workspace, maxDimension: 160, layers: .selected([layerID]), pdfMode: .preview)
        }
        tail = next
        return await withTaskCancellationHandler(operation: { await next.value }, onCancel: { next.cancel() })
    }
}
