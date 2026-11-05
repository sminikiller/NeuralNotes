import XCTest
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class LayerDrawingReaderTests: XCTestCase {
    @MainActor func testCorruptLayerRecoversOnlyItsPreviousInkAndTheRecoveredSavePreservesThatBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision += 1
        let base = stroke(x: 50), first = stroke(x: 100), second = stroke(x: 200)
        page = try await workspace.save(page, drawing: base.dataRepresentation())
        let added = try PageLayerEditing.adding(to: page, name: "Notes"); page = added.page
        page.revision += 1; page = try await workspace.save(page, drawing: first.dataRepresentation(), layerID: added.layerID)
        page.revision += 1; page = try await workspace.save(page, drawing: second.dataRepresentation(), layerID: added.layerID)
        let previous = try XCTUnwrap(PageLayers.previousDrawingFile(for: added.layerID, in: page))
        let current = try XCTUnwrap(PageLayers.drawingFile(for: added.layerID, in: page))
        try Data([0xff, 0x00]).write(to: package.appendingPathComponent(current), options: .atomic)
        let recovered = try await LayerDrawingReader.read(page: page, layerID: added.layerID, workspace: workspace)
        XCTAssertTrue(recovered.recoveredFromPrevious); XCTAssertTrue(NativeInkComparison.equal(recovered.drawing, first))
        let intact = try await LayerDrawingReader.read(page: page, layerID: page.id, workspace: workspace)
        XCTAssertFalse(intact.recoveredFromPrevious); XCTAssertTrue(NativeInkComparison.equal(intact.drawing, base))
        page.revision += 1
        page = try await workspace.save(page, drawing: recovered.drawing.dataRepresentation(), recoveredFromPrevious: true, layerID: added.layerID)
        XCTAssertEqual(PageLayers.previousDrawingFile(for: added.layerID, in: page), previous)
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(previous)), first.dataRepresentation())
        let read = try await LayerDrawingReader.read(page: page, layerID: added.layerID, workspace: workspace)
        XCTAssertFalse(read.recoveredFromPrevious); XCTAssertTrue(NativeInkComparison.equal(read.drawing, first))
    }
    @MainActor func testIntentionalEmptyCurrentLayerDoesNotReviveAnOldDrawing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID), workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage()
        let added = try PageLayerEditing.adding(to: page, name: "Empty"); page = added.page
        let previous = "drawings/previous-empty-test.drawing"; try stroke(x: 100).dataRepresentation().write(to: package.appendingPathComponent(previous))
        page.layers?[1].previousDrawingFile = previous
        page = try await workspace.saveLayerMetadata(page, expectedRevision: page.revision)
        let empty = try await LayerDrawingReader.read(page: page, layerID: added.layerID, workspace: workspace)
        XCTAssertTrue(empty.drawing.strokes.isEmpty); XCTAssertFalse(empty.recoveredFromPrevious)
    }
    @MainActor private func stroke(x: CGFloat) -> PKDrawing {
        let a = PKStrokePoint(location: .init(x: x, y: 120), timeOffset: 0, size: .init(width: 4, height: 4), opacity: 1, force: 0.7, azimuth: 0.2, altitude: 1)
        let b = PKStrokePoint(location: .init(x: x + 60, y: 140), timeOffset: 1, size: .init(width: 4, height: 4), opacity: 1, force: 0.7, azimuth: 0.2, altitude: 1)
        let native = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: 1000)))
        return PKDrawing(strokes: [native])
    }
}
