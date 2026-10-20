import SwiftUI
import NeuralNotesCore

@MainActor
struct DocumentPageViewport: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        PencilCanvas(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pencilCanvas")
            .accessibilityValue(model.canvasZoomed ? "Ingrandita" : "Pagina intera")
            .overlay(alignment: .bottomLeading) {
                if model.tool == .text {
                    HStack {
                        Text("Tocca il foglio o una casella, poi scrivi con Pencil o tastiera.").font(.caption)
                        if model.editingTextID != nil { Button("Fine") { model.endTextEdit() }.accessibilityIdentifier("pageTextDoneOverlay") }
                    }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8)
                }
            }
    }
}
