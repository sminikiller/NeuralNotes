import SwiftUI
import NeuralNotesCore

@MainActor
struct ToolOptionsPopover: View {
    @Bindable var model: EditorViewModel
    let tool: WorkspaceTool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tool.title, systemImage: tool.icon).font(.headline)
            if tool == .pen || tool == .marker { inkOptions }
            else if tool == .eraser { eraserOptions }
            else if tool.shape != nil { shapeOptions }
            else if tool == .lasso || tool == .objects { selectionOptions }
            else { otherOptions }
        }.padding(18).frame(width: 310)
            .accessibilityIdentifier("toolOptions-\(tool.rawValue)")
            .presentationCompactAdaptation(.popover)
    }
    private var inkOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool == .pen {
                Picker("Tipo di penna", selection: Binding(get: { model.writingOptions.pen }, set: { kind in model.editWriting { $0.pen = kind } })) {
                    ForEach(PenKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            }
            ToolPalettePanel(model: model)
            Toggle("Raddrizza tenendo premuto", isOn: Binding(get: { model.currentWorkspace.holdShapes }, set: { value in model.editWorkspace { $0.holdShapes = value } }))
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ShapeKind.allCases, id: \.self) { kind in
                Button { model.shapeKind = kind; model.tool = .shape; model.configureTool() } label: {
                    HStack { Label(kind.title, systemImage: kind.icon); Spacer(); if model.shapeKind == kind { Image(systemName: "checkmark") } }
                }
            }
            ToolPalettePanel(model: model)
        }
    }
    private var selectionOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Lazo PencilKit", systemImage: "lasso") { model.chooseTool(.lasso) }
            Button("Area: inchiostro e oggetti", systemImage: "rectangle.dashed") { model.chooseTool(.objects); model.selectRectangle = true }
            Toggle("Aggiungi alla selezione", isOn: $model.multiSelection)
            Button("Seleziona tutto", systemImage: "checkmark.square") { model.chooseTool(.objects); model.selectAll() }
            Button("Chiedi alla Lente AI", systemImage: "sparkles") { model.lensRequest += 1 }
        }
    }
    private var otherOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool == .ruler {
                Toggle("Righello visibile", isOn: Binding(get: { model.rulerActive }, set: { value in if value != model.rulerActive { model.chooseTool(.ruler) } }))
                Button("Penna", systemImage: "pencil.tip") { model.chooseTool(.pen) }
                Button("Evidenziatore", systemImage: "highlighter") { model.chooseTool(.marker) }
            } else if tool == .text {
                Text("Scrivi con Pencil o tastiera. La barra sopra la tastiera contiene stile, elenchi e caselle.").font(.callout)
                Button("Nuova casella", systemImage: "text.badge.plus") { model.beginTextEdit(at: CGPoint(x: 48, y: 64)) }
            } else if tool == .lens {
                Button("Apri la Lente AI", systemImage: "sparkles") { model.lensRequest += 1 }
            } else { Text("Tocca un tratto per ascoltare il punto della registrazione collegato.").font(.callout) }
        }
    }
    private func option<T>(_ key: WritableKeyPath<WritingOptions, T>) -> Binding<T> {
        Binding(get: { model.writingOptions[keyPath: key] }, set: { value in model.editWriting { $0[keyPath: key] = value } })
    }
}
