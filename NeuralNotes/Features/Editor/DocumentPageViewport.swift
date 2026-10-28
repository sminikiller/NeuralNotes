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
            .accessibilityValue(model.canvasViewportMoving ? "Zoom in corso" : (model.canvasZoomed ? "Ingrandita" : "Pagina intera"))
            .overlay(alignment: .bottomTrailing) {
                if model.searchFocus != nil { Button("Chiudi evidenziazione", systemImage: "xmark") { model.searchFocus = nil }.font(.caption).buttonStyle(.bordered).padding(8) }
            }
            .overlay(alignment: .bottomLeading) {
                if model.tool == .text {
                    PageTextControls(model: model).padding(8)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = model.recognitionNotice {
                    HStack(spacing: 12) {
                        Text(notice).font(.callout)
                        Button("Annulla") { Task { await model.performUndo() } }.font(.callout.bold())
                    }.padding(12).background(.regularMaterial, in: Capsule()).padding(12)
                        .accessibilityIdentifier("shapeRecognitionNotice")
                }
            }
    }
}
