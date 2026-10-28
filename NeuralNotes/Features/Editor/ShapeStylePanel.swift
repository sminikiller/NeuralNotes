import SwiftUI
import NeuralNotesCore

@MainActor
struct ShapeStylePanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var style = ShapeStyle()
    @State private var shape: ShapeElement?
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
                        model.applyShapeStyleAndParameters(style, template: shape); dismiss()
                    }.accessibilityIdentifier("applyShapeStyle")
                }
            }
        }.task {
            if let first = model.selectedShapes.first { style = ShapeStyle(first); shape = first }
            else { style = model.shapePreferences.style ?? .standard }
        }
    }
    private var maximumRadius: Double {
        max(1, model.selectedShapes.map { min($0.width, $0.height) / 2 }.min() ?? 80)
    }
}
