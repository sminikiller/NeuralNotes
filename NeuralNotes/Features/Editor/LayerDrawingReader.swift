import PencilKit
import NeuralNotesCore

/// Reads one owner at a time. A valid empty current drawing stays empty; a
/// corrupt/missing current file can recover only that owner's previous value.
/// The caller must pass the recovered flag to the matching layer writer.
@MainActor
enum LayerDrawingReader {
    struct Value { let drawing: PKDrawing; let recoveredFromPrevious: Bool }
    static func read(page: PageSnapshot, layerID: UUID, workspace: DocumentWorkspace) async throws -> Value {
        do {
            let data = try await workspace.drawing(page, layerID: layerID)
            try Task.checkCancellation()
            return Value(drawing: try data.map { try PKDrawing(data: $0) } ?? PKDrawing(), recoveredFromPrevious: false)
        } catch {
            let original = error
            try Task.checkCancellation()
            guard let previous = try await workspace.previousDrawing(page, layerID: layerID) else { throw original }
            return Value(drawing: try PKDrawing(data: previous), recoveredFromPrevious: true)
        }
    }
}
