import XCTest
import UIKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class DiagramEditingTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await run(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor func testLinkedBlockIsOneUndoAndDeletedTargetDetachesAtItsLatestPosition() async throws {
        try await fixture { model in
            model.addShape(.rectangle)
            let original = try XCTUnwrap(model.page), id = try XCTUnwrap(original.shapes?.first?.id)
            let newID = try XCTUnwrap(model.createDiagramBlock(from: id, side: .right))
            XCTAssertEqual(model.page?.shapes?.count, 2); XCTAssertEqual(model.page?.connectors?.count, 1)
            let created = try XCTUnwrap(model.page)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, original.shapes); XCTAssertTrue(model.page?.connectors?.isEmpty ?? true)
            await model.performRedo(); XCTAssertEqual(model.page?.shapes, created.shapes); XCTAssertEqual(model.page?.connectors, created.connectors)
            model.mutatePage("Sposta blocco") { page in page.shapes?[0].x += 40; page.shapes?[0].rotation = 30 }
            let beforeDelete = try XCTUnwrap(model.page), edge = try XCTUnwrap(beforeDelete.connectors?.first)
            let expected = ConnectorGeometry.resolve(edge.from, objects: DiagramObjects.make(beforeDelete))
            model.selectedObjectID = id; model.deleteSelectedObject()
            let detached = try XCTUnwrap(model.page?.connectors?.first?.from)
            XCTAssertNil(detached.objectID); XCTAssertEqual(detached.x, expected.x, accuracy: 0.001); XCTAssertEqual(detached.y, expected.y, accuracy: 0.001)
            XCTAssertEqual(model.page?.shapes?.first?.id, newID)
            await model.performUndo(); XCTAssertEqual(model.page?.connectors, beforeDelete.connectors); XCTAssertEqual(model.page?.shapes, beforeDelete.shapes)
        }
    }
    @MainActor func testDragPreviewFollowsDraftWithoutMutatingPageAndClearsHiddenPictures() async throws {
        try await fixture { model in
            model.addShape(.rectangle); let id = try XCTUnwrap(model.selectedObjectID)
            _ = try XCTUnwrap(model.createDiagramBlock(from: id, side: .right))
            let page = try XCTUnwrap(model.page), edge = try XCTUnwrap(page.connectors?.first)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let preview = try XCTUnwrap(host.diagramPreview)
            preview.start(page: page, moving: [id])
            var moved = try XCTUnwrap(page.shapes?.first); moved.x += 100; moved.rotation = 45
            preview.update(objects: [id: ConnectorObject(shape: moved)])
            let resolved = try XCTUnwrap(preview.endpoint(of: edge.id, fromStart: true))
            let expected = ConnectorGeometry.resolve(edge.from, objects: [id: ConnectorObject(shape: moved)])
            XCTAssertEqual(resolved.x, expected.x, accuracy: 0.001); XCTAssertEqual(resolved.y, expected.y, accuracy: 0.001)
            XCTAssertEqual(model.page, page); XCTAssertTrue(host.surface.interactionHiddenObjectIDs.contains(edge.id))
            preview.reset(); XCTAssertTrue(host.surface.interactionHiddenObjectIDs.isEmpty); XCTAssertTrue(preview.isHidden)
        }
    }
    @MainActor func testCopyPasteIncludesInternalConnectorsAndRemapsTheirTargetsInOneUndo() async throws {
        try await fixture { model in
            model.addShape(.rectangle); let id = try XCTUnwrap(model.selectedObjectID)
            _ = try XCTUnwrap(model.createDiagramBlock(from: id, side: .right))
            let original = try XCTUnwrap(model.page)
            model.selectedIDs = Set(original.shapes?.map(\.id) ?? [])
            XCTAssertTrue(model.copySelection()); await model.pasteSelection()
            let result = try XCTUnwrap(model.page), appended = Array((result.shapes ?? []).dropFirst(2)), copied = try XCTUnwrap(result.connectors?.last)
            XCTAssertEqual(result.shapes?.count, 4); XCTAssertEqual(result.connectors?.count, 2)
            XCTAssertEqual(copied.from.objectID, appended.first?.id); XCTAssertEqual(copied.to.objectID, appended.last?.id)
            XCTAssertNotEqual(copied.id, original.connectors?.first?.id); XCTAssertEqual(appended.first?.x, (original.shapes?.first?.x ?? 0) + 20)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, original.shapes); XCTAssertEqual(model.page?.connectors, original.connectors)
        }
    }
    @MainActor func testRichLabelRendersBlueGlyphsInPDFAndUndoRestoresTheOriginalShape() async throws {
        try await fixture { model in
            model.addShape(.rectangle); let page = try XCTUnwrap(model.page), shape = try XCTUnwrap(page.shapes?.first)
            let label = NSAttributedString(string: "Energia\nconservata", attributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.blue])
            var text = TextElement(text: label.string); text.fontSize = 20; text.rtf = RichText.data(label)
            model.saveDiagramLabel(.init(pageID: page.id, objectID: shape.id), text: text, autoFit: true)
            let modified = try XCTUnwrap(model.page?.shapes?.first), layout = try XCTUnwrap(DiagramLabels.shape(modified, page: model.page))
            XCTAssertEqual(layout.text.text, label.string); XCTAssertTrue(ShapeLabelRegion.rect(modified).cgRect.contains(layout.box))
            let saved = await model.flush(); XCTAssertTrue(saved)
            let url = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: url) }
            let pdf = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)), image = pdf.thumbnail(of: .init(width: 768, height: 1024), for: .cropBox)
            XCTAssertGreaterThan(bluePixels(image), 20, "Il PDF deve contenere i glifi blu, non soltanto il bordo nero della forma.")
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.first, shape)
        }
    }
    @MainActor func testEndpointDragReattachesAndUndoRestoresItsPreviousTarget() async throws {
        try await fixture { model in
            model.addShape(.rectangle); let first = try XCTUnwrap(model.selectedObjectID)
            let second = try XCTUnwrap(model.createDiagramBlock(from: first, side: .right))
            let third = ShapeElement(kind: .ellipse, x: 300, y: 600, width: 120, height: 100)
            model.mutatePage("Terzo blocco") { $0.shapes?.append(third) }
            let original = try XCTUnwrap(model.page?.connectors?.first)
            model.chooseTool(.objects); model.selectedObjectID = original.id
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let overlay = DiagramHandlesOverlay(host: host, model: model); host.diagramHandles = overlay; host.addSubview(overlay)
            let session = try XCTUnwrap(DiagramHandleSession(overlay: overlay, handle: .to))
            overlay.session = session; model.movingObjects = true
            model.canvas.panGestureRecognizer.isEnabled = false
            session.move(.init(x: 360, y: 650), suspended: false)
            XCTAssertEqual(session.targetID, third.id)
            PaperInk.configureNavigation(model.canvas, fingerDrawing: false)
            XCTAssertFalse(model.canvas.panGestureRecognizer.isEnabled)
            session.finish()
            XCTAssertEqual(model.page?.connectors?.first?.to.objectID, third.id)
            XCTAssertFalse(model.movingObjects); XCTAssertTrue(model.canvas.panGestureRecognizer.isEnabled)
            await model.performUndo(); XCTAssertEqual(model.page?.connectors?.first, original)
            XCTAssertEqual(model.page?.connectors?.first?.to.objectID, second)
        }
    }
    @MainActor func testSlowContinuousDragDoesNotBecomeAHeldFreeEndpoint() async throws {
        try await fixture { model in
            model.addShape(.rectangle); model.chooseTool(.objects)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let overlay = DiagramHandlesOverlay(host: host, model: model); host.diagramHandles = overlay; host.addSubview(overlay)
            let session = try XCTUnwrap(DiagramHandleSession(overlay: overlay, handle: .create(.right)))
            overlay.session = session; model.movingObjects = true
            let origin = session.lastPoint, scale = max(0.05, host.canvas.zoomScale)
            for step in 1...8 {
                session.move(.init(x: origin.x + Double(step) / scale, y: origin.y), suspended: false)
                try await Task.sleep(for: .milliseconds(110))
                XCTAssertFalse(session.heldFree, "La sosta si misura dallo spostamento cumulativo, non dall’ultimo campione.")
            }
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertTrue(session.heldFree); XCTAssertNil(session.targetID)
            let before = model.page; overlay.cancel()
            XCTAssertFalse(model.movingObjects); XCTAssertEqual(model.page, before)
            XCTAssertTrue(host.surface.interactionHiddenObjectIDs.isEmpty)
        }
    }
    @MainActor func testPostItConnectionUsesItsVisiblePaddedContourAndFollowsTextHeight() async throws {
        try await fixture { model in
            var text = TextElement(text: "Energia\nconservata"); text.x = 100; text.y = 150; text.width = 140; text.fontSize = 18; text.background = .yellow
            model.mutatePage("Post-it") { $0.texts = [text] }
            let initial = try XCTUnwrap(model.page), glyphs = RichText.bounds(text, pageHeight: initial.height)
            let object = try XCTUnwrap(DiagramObjects.make(initial)[text.id])
            XCTAssertEqual(object.rect.x, glyphs.minX - 8); XCTAssertEqual(object.rect.height, glyphs.height + 16)
            let copy = try XCTUnwrap(model.createDiagramBlock(from: text.id, side: .right))
            let edge = try XCTUnwrap(model.page?.connectors?.first)
            XCTAssertEqual(edge.from.x, glyphs.maxX + 8, accuracy: 0.01)
            XCTAssertEqual(edge.to.objectID, copy)
            model.mutatePage("Testo più alto") { $0.texts[0].text += "\nTerza riga\nQuarta riga" }
            let page = try XCTUnwrap(model.page), moved = ConnectorGeometry.resolve(edge.from, objects: DiagramObjects.make(page))
            XCTAssertGreaterThan(moved.y, edge.from.y)
            await model.performUndo(); XCTAssertEqual(model.page?.texts.first, text)
        }
    }
    @MainActor private func bluePixels(_ image: UIImage) -> Int {
        guard let source = image.cgImage else { return 0 }
        let width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
            context.draw(source, in: .init(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            var count = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                if pixels[i + 2] > 120, Double(pixels[i + 2]) > Double(pixels[i]) * 1.5, Double(pixels[i + 2]) > Double(pixels[i + 1]) * 1.3 { count += 1 }
            }; return count
        }
    }
}
