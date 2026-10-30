import SwiftUI
import NeuralNotesCore

@MainActor
struct ProtractorOptions: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Goniometro visibile", isOn: Binding(get: { model.protractorActive }, set: { if $0 != model.protractorActive { model.chooseTool(.protractor) } }))
            Picker("Formato", selection: Binding(get: { model.protractorGuide.kind }, set: { kind in
                guard !model.hasActiveStroke else { return }
                model.protractorGuide.kind = kind; model.editWorkspace { $0.protractorKind = kind }
            })) { Text("180°").tag(ProtractorGuide.Kind.semicircle); Text("360°").tag(ProtractorGuide.Kind.circle) }.pickerStyle(.segmented)
            Toggle("Misura angolo: due raggi", isOn: Binding(get: { model.protractorMeasure }, set: { value in
                guard !model.hasActiveStroke else { return }; model.protractorMeasure = value; model.protractorRays = []; model.guideReadout = nil
            }))
            Text("Dimensione")
            Slider(value: Binding(get: { model.protractorGuide.radius }, set: { if !model.hasActiveStroke { model.protractorGuide.radius = $0 } }), in: 60...1200)
            if let value = model.guideReadout { Text(value).font(.headline.monospacedDigit()) }
            Button("Azzera misure", systemImage: "arrow.counterclockwise") {
                guard !model.hasActiveStroke else { return }; model.protractorRays = []; model.guideReadout = nil
            }
            Text("Con Pencil parti vicino al bordo per un arco, dal centro per un raggio. Il gesto resta agganciato fino al rilascio. Trascina il corpo con un dito; due dita ruotano e il pizzico cambia dimensione. Con scrittura a dito, sposta con due dita.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
