import SwiftUI
import NeuralNotesCore

/// Preparing a page containing several owners is asynchronous. Never decode
/// their native archives from SwiftUI's body or hide ink outside the base.
@MainActor
struct LayerAreaRecognition: View {
    let model: EditorViewModel
    let page: PageSnapshot
    @State private var image: UIImage?
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let image {
                AreaRecognitionPanel(image: image, workspace: model.workspace, pageID: page.id) { text in
                    guard model.page?.id == page.id else { return }
                    model.page?.recognizedText += "\n" + text; model.drawingChanged()
                }
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if let failure { Text(failure).foregroundStyle(.secondary) }
                        else { ProgressView("Preparazione della pagina…") }
                    }.padding().navigationTitle("OCR di una selezione")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
                }
            }
        }.task(id: page.id) {
            do {
                let value = try await DocumentServices.compositeImage(page: page, drawing: model.canvas.drawing,
                    drawingLayerID: model.activeLayerID, workspace: model.workspace, layers: .all)
                try Task.checkCancellation(); image = value
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }
}
