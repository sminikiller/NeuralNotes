import SwiftUI
import NeuralNotesCore

@MainActor
struct ShapeStylePanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var style = NeuralNotesCore.ShapeStyle()
    @State private var shape: ShapeElement?
    @State private var sourcePageID: UUID?
    @State private var sourceIDs = Set<UUID>()
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Lo stile si applica alle forme selezionate in un solo passo di annulla.").font(.callout) }
                ShapeStyleFields(style: $style, maximumRadius: maximumRadius)
                if let shape {
                    Section("\(shape.kind.title)") {
                        ShapeParametersFields(shape: Binding(get: { self.shape ?? shape }, set: { self.shape = $0 }))
                    }
                }
                Section {
                    Button("Usa come predefinito", systemImage: "star") { model.editShapePreferences { $0.style = style } }
                    Text("Il predefinito resta nel Workspace di questo quaderno.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stile forme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") {
                        guard model.page?.id == sourcePageID, model.selectedIDs == sourceIDs else { return }
                        model.applyShapeStyleAndParameters(style, template: shape); dismiss()
                    }.accessibilityIdentifier("applyShapeStyle").disabled(!loaded || model.page?.id != sourcePageID || model.selectedIDs != sourceIDs)
                }
            }
        }.task {
            guard !loaded else { return }
            sourcePageID = model.page?.id; sourceIDs = model.selectedIDs
            if let first = model.selectedShapes.first { style = NeuralNotesCore.ShapeStyle(first); shape = first }
            else { style = model.shapePreferences.style ?? .standard }
            loaded = true
        }
    }
    private var maximumRadius: Double {
        max(1, model.selectedShapes.map { min($0.width, $0.height) / 2 }.min() ?? 80)
    }
}

@MainActor
struct NewShapeStylePanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var style = NeuralNotesCore.ShapeStyle.standard
    var body: some View {
        NavigationStack {
            Form { ShapeStyleFields(style: $style) }
                .navigationTitle("Nuove forme")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva stile") {
                            model.editShapePreferences { $0.style = style }
                            model.restoreToolPalette(); model.configureTool(); dismiss()
                        }
                    }
                }
        }.task {
            style = model.shapePreferences.style ?? .standard
            if style.color == nil { style.color = InkColor(model.ink) }
            if style.width == nil { style.width = model.thickness }
        }
    }
}
