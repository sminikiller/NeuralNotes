import SwiftUI
import PencilKit
import NeuralNotesCore

extension PenKind {
    var native: PKInkingTool.InkType {
        switch self { case .pen: return .pen; case .pencil: return .pencil; case .monoline: return .monoline
        case .fountainPen: return .fountainPen; case .watercolor: return .watercolor; case .crayon: return .crayon }
    }
}
@MainActor
extension EditorViewModel {
    var writingOptions: WritingOptions { currentWorkspace.writing ?? WritingOptions() }
    func editWriting(_ edit: (inout WritingOptions) -> Void) {
        guard !hasActiveStroke else { return }
        var options = writingOptions; edit(&options); guard options.isValid else { return }
        editWorkspace { $0.writing = options }; configureTool()
    }
    func usePreset(_ preset: PenPreset) {
        guard !hasActiveStroke else { return }
        tool = .pen; editWriting { $0.pen = preset.kind }; ink = preset.color.color; thickness = preset.width
        rememberPalette(); configureTool()
    }
    func eraseMarkers(samples: [StrokeSample]) {
        guard hasLease, !samples.isEmpty else { return }
        let before = captureEdit(ink: true)
        let (drawing, changed) = SelectiveInkEraser.erase(canvas.drawing, samples: samples, width: writingOptions.eraserWidth, wholeStroke: writingOptions.eraser == .stroke)
        guard changed else { return }
        canvas.drawing = drawing; recordEdit(before, label: "Cancella evidenziatore"); drawingChanged()
        if writingOptions.returnToPen { chooseTool(.pen) }
    }
}
@MainActor
struct WritingToolsPanel: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Form {
            Section("Penna") {
                Picker("Tipo", selection: option(\.pen)) { ForEach(PenKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                Slider(value: Binding(get: { model.thickness }, set: { model.chooseWidth($0) }), in: 0.5...40)
                Text("Spessore \(model.thickness, specifier: "%.1f") pt")
                ColorPicker("Colore", selection: Binding(get: { model.ink }, set: { model.chooseInk($0) }), supportsOpacity: false)
                Button("Salva tra le mie penne", systemImage: "star") {
                    let preset = PenPreset(kind: model.writingOptions.pen, color: InkColor(model.ink), width: model.thickness)
                    model.editWriting { $0.presets.append(preset) }
                }.disabled(model.writingOptions.presets.count >= 5)
                ForEach(model.writingOptions.presets) { preset in
                    HStack {
                        Button { model.usePreset(preset) } label: { Label("\(preset.kind.title) · \(preset.width, specifier: "%.1f") pt", systemImage: "pencil.tip").foregroundStyle(preset.color.color) }
                        Spacer()
                        Button(role: .destructive) { model.editWriting { $0.presets.removeAll { $0.id == preset.id } } } label: { Image(systemName: "minus.circle") }
                    }
                }
            }
            Section("Gomma") {
                Picker("Cancellazione", selection: option(\.eraser)) { Text("Parziale").tag(EraserKind.partial); Text("Tratto intero").tag(EraserKind.stroke) }
                Slider(value: option(\.eraserWidth), in: 4...100)
                Text("Larghezza \(model.writingOptions.eraserWidth, specifier: "%.0f") pt")
                Toggle("Solo evidenziatore", isOn: option(\.markerOnly))
                Toggle("Torna alla penna dopo aver cancellato", isOn: option(\.returnToPen))
            }
        }.navigationTitle("Penne e gomma")
    }
    private func option<T>(_ key: WritableKeyPath<WritingOptions, T>) -> Binding<T> {
        Binding(get: { model.writingOptions[keyPath: key] }, set: { value in model.editWriting { $0[keyPath: key] = value } })
    }
}
