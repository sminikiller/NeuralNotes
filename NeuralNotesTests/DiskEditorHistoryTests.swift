import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class DiskEditorHistoryTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let writer = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: writer); await model.open()
        do { try await body(model, root); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func snapshot(_ page: PageSnapshot, model: EditorViewModel, root: URL, drawing: Data? = nil) async throws -> PageEditSnapshot {
        let builder = try PageEditSnapshotBuilder(documentID: model.workspace.documentID, parent: root.appendingPathComponent("undo"))
        try await builder.append(page, drawing: drawing, sourcePackage: model.workspace.package)
        return try await builder.finish()
    }
    @MainActor func testOneUndoRestoresDeletedImageAfterCleanupAndKeepsNativeInkExact() async throws {
        try await fixture { model, root in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { renderer in
                UIColor.red.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            let data = try XCTUnwrap(image.pngData()), file = try await model.workspace.storeImage(data)
            let points = [CGPoint(x: 50, y: 100), CGPoint(x: 250, y: 140)].enumerated().map { i, p in
                PKStrokePoint(location: p, timeOffset: Double(i) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 0.8, azimuth: 0, altitude: .pi / 2)
            }
            model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
            model.page?.images = [ImageElement(file: file, width: 100, height: 100)]; model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved); model.history.clear()
            let original = try XCTUnwrap(model.page), ink = model.canvas.drawing.dataRepresentation()
            let before = try await snapshot(original, model: model, root: root)
            var empty = original; empty.images = []
            let after = try await snapshot(empty, model: model, root: root)
            let order = model.pages.map(\.id)
            let change = EditorDiskChange(before: before, after: after, beforeOrder: order, afterOrder: order, beforePage: original.id, afterPage: original.id)
            try await model.applyDiskChange(change, label: "Elimina immagini")
            XCTAssertTrue(model.page?.images.isEmpty == true); XCTAssertTrue(model.canUndo)
            _ = try await model.workspace.cleanUnusedFiles()
            let removed = try await model.workspace.url(file)
            XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
            await model.performUndo()
            XCTAssertNil(model.error); XCTAssertEqual(model.page?.images, original.images)
            XCTAssertEqual(try Data(contentsOf: removed), data)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, try PKDrawing(data: ink)))
            XCTAssertFalse(model.canUndo); XCTAssertTrue(model.canRedo)
            await model.performRedo()
            XCTAssertNil(model.error); XCTAssertTrue(model.page?.images.isEmpty == true)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, try PKDrawing(data: ink)))
        }
    }
    @MainActor func testInitialDiskEditRefusesARevisionChangedAfterPreparation() async throws {
        try await fixture { model, root in
            let original = try XCTUnwrap(model.page), ink = model.canvas.drawing.dataRepresentation()
            let before = try await snapshot(original, model: model, root: root, drawing: ink)
            var removed = original; removed.texts = []
            let after = try await snapshot(removed, model: model, root: root, drawing: ink)
            var external = original; external.revision += 1; external.texts = [TextElement(text: "Modifica arrivata dopo")]
            let newer = try await model.workspace.save(external, drawing: ink)
            let order = model.pages.map(\.id)
            let change = EditorDiskChange(before: before, after: after, beforeOrder: order, afterOrder: order, beforePage: original.id, afterPage: original.id)
            do {
                try await model.applyDiskChange(change, label: "Rifiutare")
                XCTFail("Una revisione obsoleta non deve essere sovrascritta.")
            } catch WorkspaceFailure.staleRevision { }
            catch { XCTFail("Errore inatteso: \(error)") }
            let preserved = try await model.workspace.pageSnapshot(original.id)
            XCTAssertEqual(preserved, newer); XCTAssertFalse(model.canUndo)
        }
    }
    @MainActor func testReadFailureAfterDurableCommitStillKeepsTheUndoEntry() async throws {
        try await fixture { model, root in
            let page = try XCTUnwrap(model.page), ink = PKDrawing().dataRepresentation()
            XCTAssertNil(page.drawingFile)
            let before = try await snapshot(page, model: model, root: root, drawing: ink)
            let after = try await snapshot(page, model: model, root: root, drawing: Data([1, 2, 3]))
            let order = model.pages.map(\.id)
            let change = EditorDiskChange(before: before, after: after, beforeOrder: order, afterOrder: order, beforePage: page.id, afterPage: page.id)
            try await model.applyDiskChange(change, label: "Errore di lettura simulato")
            XCTAssertNotNil(model.error); XCTAssertTrue(model.canUndo, "L’annulla deve esistere anche se la rilettura dopo il commit fallisce.")
            await model.performUndo()
            XCTAssertFalse(model.canUndo); XCTAssertTrue(model.canRedo)
            let restored = try await model.workspace.pageSnapshot(page.id)
            let data = try await model.workspace.drawing(restored)
            XCTAssertTrue(try PKDrawing(data: XCTUnwrap(data)).strokes.isEmpty)
        }
    }
}
