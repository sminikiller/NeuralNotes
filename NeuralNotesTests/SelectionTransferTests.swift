import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class SelectionTransferTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func ink() -> PKDrawing {
        let controls = [CGPoint(x: 80, y: 100), CGPoint(x: 250, y: 140)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 0.8, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controls, creationDate: Date()))])
    }
    @MainActor func testMoveToNewPageAndUndoRestoreOrderImagesAndExactInkTogether() async throws {
        try await fixture { model in
            let picture = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { item in UIColor.red.setFill(); item.fill(CGRect(x: 0, y: 0, width: 30, height: 20)) }
            let file = try await model.workspace.storeImage(try XCTUnwrap(picture.pngData()))
            var image = ImageElement(file: file, width: 160, height: 100)
            image.perspective = .full; image.photoQuarterTurns = 1; image.photoEnhanced = true
            model.page?.paper = .grid; model.page?.width = 600; model.page?.height = 800
            model.page?.images = [image]; model.canvas.drawing = ink(); model.drawingChanged()
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let origin = try XCTUnwrap(model.page), bytes = model.canvas.drawing.dataRepresentation(), order = model.pages.map(\.id)
            model.history.clear(); model.selectedIDs = [image.id]; model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            await model.transferSelection(to: nil, copy: false)
            XCTAssertNil(model.error); XCTAssertEqual(model.pages.count, 2)
            let destination = try XCTUnwrap(model.page)
            XCTAssertNotEqual(destination.id, origin.id); XCTAssertEqual(destination.paper, .grid)
            XCTAssertEqual(destination.width, 600); XCTAssertNil(destination.pdfFile)
            XCTAssertEqual(destination.images.first?.perspective, .full); XCTAssertEqual(destination.images.first?.photoQuarterTurns, 1)
            XCTAssertNotEqual(destination.images.first?.id, image.id)
            let sourceAfter = try await model.workspace.pageSnapshot(origin.id)
            XCTAssertTrue(sourceAfter.images.isEmpty); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            _ = try await model.workspace.cleanUnusedFiles()
            await model.performUndo()
            XCTAssertNil(model.error); XCTAssertEqual(model.pages.map(\.id), order); XCTAssertEqual(model.page?.id, origin.id)
            XCTAssertEqual(model.page?.images, [image]); XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            XCTAssertFalse(model.canUndo)
            await model.performRedo()
            XCTAssertNil(model.error); XCTAssertEqual(model.page?.id, destination.id); XCTAssertEqual(model.pages.count, 2)
            await model.performUndo(); XCTAssertEqual(model.pages.map(\.id), order)
        }
    }
    @MainActor func testCopyToNewPageBeforeKeepsSourceAndRenewsNativeStrokeIdentities() async throws {
        try await fixture { model in
            let note = TextElement(text: "Conservare la fonte")
            model.page?.texts = [note]; model.canvas.drawing = ink(); model.drawingChanged()
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let origin = try XCTUnwrap(model.page), bytes = model.canvas.drawing.dataRepresentation()
            let signature = EditorInkSignatures.make(model.canvas.drawing)
            model.history.clear(); model.selectedIDs = [note.id]; model.selectionIncludesInk = true
            await model.transferSelection(to: nil, copy: true, newPageAfter: false)
            XCTAssertNil(model.error)
            let destination = try XCTUnwrap(model.page)
            XCTAssertEqual(model.pages.map(\.id), [destination.id, origin.id])
            XCTAssertNotEqual(destination.texts.first?.id, note.id); XCTAssertEqual(destination.texts.first?.text, note.text)
            XCTAssertNotEqual(EditorInkSignatures.make(model.canvas.drawing), signature)
            let source = try await model.workspace.pageSnapshot(origin.id)
            XCTAssertEqual(source, origin, "Copia non scrive neppure una nuova intestazione sulla pagina di origine.")
            let sourceInk = try await model.workspace.drawing(source); XCTAssertEqual(sourceInk, bytes)
            await model.performUndo(); XCTAssertEqual(model.pages.map(\.id), [origin.id]); XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            XCTAssertFalse(model.canUndo)
            await model.performRedo(); XCTAssertEqual(model.page?.id, destination.id)
            XCTAssertEqual(model.pages.map(\.id), [destination.id, origin.id])
        }
    }
    @MainActor func testCopyBetweenDifferentSizesFitsRichTextAndDoesNotAlterTheSource() async throws {
        try await fixture { model in
            var text = TextElement(text: "Testo ricco da scalare"); text.x = 100; text.width = 500; text.fontSize = 32
            text.rtf = RichText.data(NSAttributedString(string: text.text, attributes: [.font: UIFont.boldSystemFont(ofSize: 32)]))
            model.page?.texts = [text]; model.drawingChanged()
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let source = try XCTUnwrap(model.page)
            var small = PageSnapshot(); small.width = 240; small.height = 320
            let target = try await model.workspace.addPage(small); model.pages = try await model.workspace.pages()
            model.selectedIDs = [text.id]; model.history.clear()
            await model.transferSelection(to: target.id, copy: true)
            XCTAssertNil(model.error)
            let copied = try XCTUnwrap(model.page?.texts.first)
            XCTAssertLessThan(copied.width, 240); XCTAssertLessThan(copied.fontSize, 32); XCTAssertNotNil(copied.rtf)
            XCTAssertEqual(copied.text, text.text); XCTAssertNotEqual(copied.id, text.id)
            let unchanged = try await model.workspace.pageSnapshot(source.id); XCTAssertEqual(unchanged, source)
            await model.performUndo(); XCTAssertNil(model.error); XCTAssertEqual(model.page?.id, source.id)
            let restored = try await model.workspace.pageSnapshot(target.id); XCTAssertTrue(restored.texts.isEmpty)
            await model.performRedo(); XCTAssertEqual(model.page?.texts.first, copied)
        }
    }
    @MainActor func testCopyRenewsInternalTargetsAndDetachesTheUnselectedExternalTarget() async throws {
        try await fixture { model in
            let a = ShapeElement(kind: .rectangle, x: 100, y: 100, width: 80, height: 60)
            let b = ShapeElement(kind: .ellipse, x: 300, y: 100, width: 80, height: 60)
            let outside = ShapeElement(kind: .rectangle, x: 300, y: 300, width: 80, height: 60)
            var internalEdge = ConnectorElement(from: .init(objectID: a.id, x: 0, y: 0), to: .init(objectID: b.id, x: 0, y: 0))
            internalEdge.label = "Interno"
            var externalEdge = ConnectorElement(from: .init(objectID: a.id, x: 0, y: 0), to: .init(objectID: outside.id, x: 0, y: 0))
            externalEdge.label = "Esterno"
            model.page?.shapes = [a, b, outside]; model.page?.connectors = [internalEdge, externalEdge]; model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved)
            let origin = try XCTUnwrap(model.page)
            model.selectedIDs = [a.id, b.id, externalEdge.id]; model.history.clear()
            await model.transferSelection(to: nil, copy: true)
            XCTAssertNil(model.error)
            let copied = try XCTUnwrap(model.page), ids = Set((copied.shapes ?? []).map(\.id))
            XCTAssertEqual(copied.shapes?.count, 2); XCTAssertEqual(copied.connectors?.count, 2)
            XCTAssertTrue(ids.isDisjoint(with: [a.id, b.id, outside.id]))
            let inside = try XCTUnwrap(copied.connectors?.first { $0.label == "Interno" })
            XCTAssertTrue(ids.contains(try XCTUnwrap(inside.from.objectID))); XCTAssertTrue(ids.contains(try XCTUnwrap(inside.to.objectID)))
            let detached = try XCTUnwrap(copied.connectors?.first { $0.label == "Esterno" })
            XCTAssertTrue(ids.contains(try XCTUnwrap(detached.from.objectID))); XCTAssertNil(detached.to.objectID)
            XCTAssertGreaterThan(detached.to.x, 0); XCTAssertGreaterThan(detached.to.y, 0)
            let unchanged = try await model.workspace.pageSnapshot(origin.id); XCTAssertEqual(unchanged, origin)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, origin.shapes); XCTAssertEqual(model.page?.connectors, origin.connectors)
            await model.performRedo(); XCTAssertEqual(model.page?.connectors, copied.connectors)
        }
    }
    @MainActor func testNewPageAtTheEndIsIndependentOfTheCurrentPagePosition() async throws {
        try await fixture { model in
            model.addStickyNote("Da spostare alla fine")
            let first = try XCTUnwrap(model.page)
            await model.addPage(); await model.addPage()
            await model.select(first)
            let order = model.pages.map(\.id), text = try XCTUnwrap(model.page?.texts.first)
            model.selectedIDs = [text.id]; model.history.clear()
            await model.transferSelection(to: nil, copy: false, newPageAtEnd: true)
            XCTAssertNil(model.error); XCTAssertEqual(model.pages.count, 4)
            let destinationID = try XCTUnwrap(model.page?.id)
            XCTAssertEqual(model.pages.map(\.id), order + [destinationID])
            XCTAssertEqual(model.page?.texts.first?.text, text.text)
            await model.performUndo(); XCTAssertEqual(model.pages.map(\.id), order)
            XCTAssertEqual(model.page?.texts, [text]); XCTAssertFalse(model.canUndo)
            await model.performRedo(); XCTAssertEqual(model.pages.map(\.id), order + [destinationID])
        }
    }
}
