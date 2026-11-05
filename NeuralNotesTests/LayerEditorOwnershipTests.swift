import XCTest
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class LayerEditorOwnershipTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, UUID, PKDrawing, PKDrawing) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        let store = try NativeDocumentStore(root: root); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage()
        let base = PKDrawing(strokes: [stroke(x: 60)]), upper = PKDrawing(strokes: [stroke(x: 200)])
        page.revision += 1; page = try await workspace.save(page, drawing: base.dataRepresentation())
        let added = try PageLayerEditing.adding(to: page, name: "Annotazioni"); page = added.page
        page.revision += 1; _ = try await workspace.save(page, drawing: upper.dataRepresentation(), layerID: added.layerID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await body(model, added.layerID, base, upper); _ = await model.close() }
        catch { _ = await model.close(); throw error }
    }

    @MainActor func testOwnerSwitchSavesOnlyItsOwnNativeInkAndCrossLayerUndoRedoRestoresThatOwner() async throws {
        try await fixture { model, layer, base, upper in
            let pageID = try XCTUnwrap(model.page?.id)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            let baseFile = model.page?.drawingFile
            await model.selectLayer(layer)
            XCTAssertEqual(model.drawingLayerID, layer)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
            let before = model.captureEdit(ink: true)
            let next = PKDrawing(strokes: upper.strokes + [self.stroke(x: 320)])
            model.replaceInkSession(with: next); model.recordEdit(before, label: "Inchiostro"); model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved)
            XCTAssertEqual(model.page?.drawingFile, baseFile)
            let stored = try await model.workspace.pageSnapshot(pageID)
            let storedBase = try await LayerDrawingReader.read(page: stored, layerID: pageID, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(storedBase.drawing, base))
            await model.selectLayer(pageID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            await model.performUndo()
            XCTAssertEqual(model.drawingLayerID, layer)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
            await model.selectLayer(pageID)
            await model.performRedo()
            XCTAssertEqual(model.drawingLayerID, layer)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, next))
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let final = try await model.workspace.pageSnapshot(pageID)
            let finalBase = try await LayerDrawingReader.read(page: final, layerID: pageID, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(finalBase.drawing, base))
            XCTAssertEqual(model.canvas.drawing.strokes[1].path[0].force, next.strokes[1].path[0].force)
            XCTAssertEqual(model.canvas.drawing.strokes[1].path[0].azimuth, next.strokes[1].path[0].azimuth)
        }
    }

    @MainActor func testUnreadableDestinationNeverReplacesOrChangesTheCurrentOwner() async throws {
        try await fixture { model, layer, base, _ in
            let page = try XCTUnwrap(model.page)
            let path = try XCTUnwrap(PageLayers.drawingFile(for: layer, in: page))
            let file = try await model.workspace.url(path)
            try Data([0xff, 0x00]).write(to: file, options: .atomic)
            await model.selectLayer(layer)
            XCTAssertEqual(model.drawingLayerID, page.id)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            XCTAssertNotNil(model.error); XCTAssertFalse(model.dirty); XCTAssertFalse(model.navigating)
        }
    }

    @MainActor func testHiddenOrLockedDestinationCannotStealTheLiveCanvas() async throws {
        try await fixture { model, layer, base, _ in
            var page = try XCTUnwrap(model.page)
            page = try PageLayerEditing.lock(layer, locked: true, in: page)
            page = try await model.workspace.saveLayerMetadata(page, expectedRevision: page.revision)
            try await model.load(page)
            await model.selectLayer(layer)
            XCTAssertEqual(model.drawingLayerID, page.id)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            page = try PageLayerEditing.lock(layer, locked: false, in: page)
            page = try PageLayerEditing.visibility(layer, visible: false, in: page)
            page = try await model.workspace.saveLayerMetadata(page, expectedRevision: page.revision)
            try await model.load(page)
            await model.selectLayer(layer)
            XCTAssertEqual(model.drawingLayerID, page.id)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
        }
    }

    @MainActor private func stroke(x: CGFloat) -> PKStroke {
        let a = PKStrokePoint(location: CGPoint(x: x, y: 120), timeOffset: 0,
            size: CGSize(width: 4, height: 5), opacity: 0.9, force: 0.72, azimuth: 0.3, altitude: 1)
        let b = PKStrokePoint(location: CGPoint(x: x + 60, y: 140), timeOffset: 0.2,
            size: CGSize(width: 6, height: 7), opacity: 1, force: 0.83, azimuth: 0.5, altitude: 0.9)
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: Double(x))))
    }
}
