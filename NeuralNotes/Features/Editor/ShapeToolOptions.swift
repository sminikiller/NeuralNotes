import SwiftUI
import NeuralNotesCore

@MainActor
struct ShapeToolOptions: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ShapeKind.allCases, id: \.self) { kind in
                    Button { model.chooseShape(kind) } label: {
                        VStack(spacing: 5) { Image(systemName: kind.icon).font(.title3); Text(kind.title).font(.caption).multilineTextAlignment(.center) }
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(model.shapeKind == kind ? Brand.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("shapeKind-\(kind.rawValue)")
                        .accessibilityAddTraits(model.shapeKind == kind ? .isSelected : [])
                }
            }
            if model.shapeKind == .polygon || model.shapeKind == .star {
                Stepper(model.shapeKind == .star ? "Punte: \(sides)" : "Lati: \(sides)", value: Binding(
                    get: { sides }, set: { value in model.editShapePreferences { $0.sides = value } }), in: (model.shapeKind == .star ? 4 : 3)...12)
            }
            if model.shapeKind == .star {
                Slider(value: Binding(get: { model.shapePreferences.innerRatio ?? 0.5 }, set: { value in model.editShapePreferences { $0.innerRatio = value } }), in: 0.2...0.8)
                    .accessibilityLabel("Raggio interno della stella")
            }
            Text(model.shapeKind == .arc ? "Trascina tra i due estremi della corda. Poi seleziona l’arco e usa la maniglia centrale per curvarlo." : "Trascina sul foglio. Con Oggetti puoi modificare le maniglie e lo stile.")
                .font(.caption).foregroundStyle(.secondary)
            ToolPalettePanel(model: model)
        }
    }
    private var sides: Int { max(model.shapeKind == .star ? 4 : 3, model.shapePreferences.sides ?? (model.shapeKind == .star ? 5 : 6)) }
}

@MainActor
struct ShapeRecognitionPanel: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Form {
            Section("Riconoscimento forme") { ShapeRecognitionModePicker(model: model) }
            Section("Converti in") {
                Picker("Risultato con la penna", selection: Binding(get: { model.shapePreferences.output ?? .editable }, set: { value in model.editShapePreferences { $0.output = value } })) {
                    ForEach(ShapeRecognitionOutput.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("L’evidenziatore rimane un tratto diritto. La modalità automatica è prudente vicino alla scrittura. Annulla ripristina il tratto originale.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Forme da riconoscere") {
                ForEach(ShapeKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(get: { model.shapePreferences.kinds.contains(kind) }, set: { enabled in
                        model.editShapePreferences { settings in
                            var kinds = settings.kinds; kinds.removeAll { $0 == kind }; if enabled { kinds.append(kind) }; settings.enabledKinds = kinds
                        }
                    }))
                }
            }
        }.navigationTitle("Riconoscimento forme")
    }
}

@MainActor
struct ShapeRecognitionModePicker: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Picker("Riconoscimento forme", selection: Binding(get: { model.recognitionMode }, set: { mode in model.editShapePreferences { $0.mode = mode } })) {
            ForEach(ShapeRecognitionMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("shapeRecognitionMode")
    }
}
