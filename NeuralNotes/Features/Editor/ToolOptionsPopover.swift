import SwiftUI
import NeuralNotesCore

@MainActor
struct ToolOptionsPopover: View {
    @Bindable var model: EditorViewModel
    let tool: WorkspaceTool
    @State private var recognitionDetails = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Label(tool.title, systemImage: tool.icon).font(.headline)
            if tool == .pen || tool == .marker { inkOptions }
            else if tool == .eraser { eraserOptions }
            else if tool.shape != nil { shapeOptions }
            else if tool == .lasso || tool == .objects { selectionOptions }
            else { otherOptions }
        }.padding(18) }.frame(width: 340).frame(maxHeight: 620)
            .accessibilityIdentifier("toolOptions-\(tool.rawValue)")
            .presentationCompactAdaptation(.popover)
            .sheet(isPresented: $recognitionDetails) {
                NavigationStack {
                    ShapeRecognitionPanel(model: model)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { recognitionDetails = false } } }
                }
            }
    }
    private var inkOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool == .pen {
                Picker("Tipo di penna", selection: Binding(get: { model.writingOptions.pen }, set: { kind in model.editWriting { $0.pen = kind } })) {
                    ForEach(PenKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            }
            ToolPalettePanel(model: model)
            if tool == .marker { MarkerOptions(model: model) }
            ShapeRecognitionModePicker(model: model).pickerStyle(.menu)
            Button("Forme da riconoscere e risultato", systemImage: "square.on.circle") { recognitionDetails = true }
            if tool == .pen {
                Button("Salva questa penna", systemImage: "star") {
                    let preset = PenPreset(kind: model.writingOptions.pen, color: InkColor(model.ink), width: model.thickness)
                    model.editWriting { $0.presets.append(preset) }
                }.disabled(model.writingOptions.presets.count >= 5)
                ForEach(model.writingOptions.presets) { preset in
                    Button("\(preset.kind.title) · \(preset.width, specifier: "%.1f") pt") { model.usePreset(preset) }
                }
            }
        }
    }
    private var eraserOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tipo di gomma", selection: option(\.eraser)) {
                Text("Parziale").tag(EraserKind.partial); Text("Tratto intero").tag(EraserKind.stroke)
            }.pickerStyle(.segmented)
            Slider(value: option(\.eraserWidth), in: 4...100)
            Text("\(model.writingOptions.eraserWidth, specifier: "%.0f") pt").font(.caption.monospacedDigit())
            Toggle("Solo evidenziatore", isOn: option(\.markerOnly))
            Toggle("Torna alla penna", isOn: option(\.returnToPen))
        }
    }
    private var shapeOptions: some View {
        ShapeToolOptions(model: model)
    }
    private var selectionOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Lazo PencilKit", systemImage: "lasso") { model.chooseTool(.lasso) }
            Button("Lazo libero: inchiostro e oggetti", systemImage: "lasso.and.sparkles") { model.chooseTool(.objects); model.selectRectangle = false; model.selectFreehand = true }
            Button("Area: inchiostro e oggetti", systemImage: "rectangle.dashed") { model.chooseTool(.objects); model.selectFreehand = false; model.selectRectangle = true }
            Toggle("Aggiungi alla selezione", isOn: $model.multiSelection)
            Text("Spessore selezione · \(model.selectionWidth, specifier: "%.1f") pt").font(.caption)
            Slider(value: $model.selectionWidth, in: 0.5...40)
            Button("Applica spessore a tratti e forme") { model.changeSelectionWidth(model.selectionWidth) }
            Button("Seleziona tutto", systemImage: "checkmark.square") { model.chooseTool(.objects); model.selectAll() }
            MoveSelectionMenu(model: model)
            Button("Chiedi alla Lente AI", systemImage: "sparkles") { model.lensAskAboutSelection() }
        }
    }
    private var otherOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool == .ruler {
                Text("Con il righello attivo la penna segue sempre il bordo scelto all’inizio del tratto, anche se la punta si allontana. Sposta e ruota con due dita, pizzica per allungare; vicino a 0°, 45° e 90° l’angolo si aggancia.").font(.caption).foregroundStyle(.secondary)
                Toggle("Righello visibile", isOn: Binding(get: { model.rulerActive }, set: { value in if value != model.rulerActive { model.chooseTool(.ruler) } }))
                Text("Lunghezza del righello")
                Slider(value: Binding(get: { model.rulerGuide.length }, set: { model.rulerGuide.length = $0 }), in: 240...1800)
                Button("Penna", systemImage: "pencil.tip") { model.chooseTool(.pen) }
                Button("Evidenziatore", systemImage: "highlighter") { model.chooseTool(.marker) }
            } else if tool == .protractor {
                ProtractorOptions(model: model)
            } else if tool == .text {
                Text("Scrivi con Pencil o tastiera. I comandi nel piccolo overlay sul foglio contengono stile, elenchi e tastiera.").font(.callout)
                Button("Nuova casella", systemImage: "text.badge.plus") { model.beginTextEdit(at: CGPoint(x: 48, y: 64)) }
            } else if tool == .lens {
                Text("Sottolinea un nome o un termine per una nota collegata al testo, tocca una parola per spiegarla, cerchia o trascina per chiedere. Trascina le note per spostarle; il cerchietto le riduce a 💡.").font(.callout)
                Button("Note della Lente", systemImage: "list.bullet.rectangle.portrait") { model.showLensPanel(.notes) }
                Button("Chat sulla pagina", systemImage: "bubble.left.and.text.bubble.right") { model.requestLens() }
            } else { Text("Tocca un tratto per ascoltare il punto della registrazione collegato.").font(.callout) }
        }
    }
    private func option<T>(_ key: WritableKeyPath<WritingOptions, T>) -> Binding<T> {
        Binding(get: { model.writingOptions[keyPath: key] }, set: { value in model.editWriting { $0[keyPath: key] = value } })
    }
}
