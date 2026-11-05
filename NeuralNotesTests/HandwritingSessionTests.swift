import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class HandwritingSessionTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.recognizedText = "Le parole originali non cambiano"; page.revision += 1
        var strokes: [PKStroke] = []
        for row in 0..<5 {
            let controls = (0..<20).map { index in
                PKStrokePoint(location: CGPoint(x: 80 + Double(index) * 9, y: 100 + Double(row) * 70 + Double(index) * Double(row + 1) * 0.6),
                    timeOffset: Double(index) * 0.02, size: CGSize(width: 4, height: 4), opacity: 1,
                    force: CGFloat(index % 7) / 8, azimuth: 0.2, altitude: 1.1, secondaryScale: 0.75)
            }
            strokes.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controls,
                creationDate: Date(timeIntervalSince1970: Double(1000 + row))), transform: .identity, mask: nil, randomSeed: UInt32(row + 20)))
        }
        _ = try await workspace.save(page, drawing: PKDrawing(strokes: strokes).dataRepresentation())
        let model = EditorViewModel(workspace: workspace); await model.open()
        model.tool = .objects; model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(strokes.indices)
        do { try await body(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func ready(_ model: EditorViewModel) async throws -> HandwritingSession {
        let session = try XCTUnwrap(model.handwriting)
        let deadline = Date().addingTimeInterval(10)
        while session.preparing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.preparing, "Await the proposal state rather than a guessed fixed delay")
        XCTAssertTrue(session.canApply, session.message ?? "No applicable preview")
        return session
    }
    @MainActor func testPreviewDoesNotSaveAndApplyIsOneUndoWithExactNativeRestorationAndUnchangedOCR() async throws {
        try await fixture { model in
            let original = model.canvas.drawing, header = try XCTUnwrap(model.page)
            XCTAssertFalse(model.canUndo); XCTAssertFalse(model.dirty)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            XCTAssertTrue(NativeInkComparison.equal(original, model.canvas.drawing)); XCTAssertEqual(model.page, header)
            XCTAssertFalse(model.canUndo); XCTAssertFalse(model.dirty)
            XCTAssertNotNil(session.preview); session.apply()
            XCTAssertNil(model.handwriting); XCTAssertTrue(model.canUndo)
            XCTAssertEqual(model.page?.recognizedText, header.recognizedText)
            let modified = model.canvas.drawing
            XCTAssertFalse(NativeInkComparison.equal(modified, original))
            XCTAssertEqual(EditorInkSignatures.make(modified), EditorInkSignatures.make(original))
            for stroke in modified.strokes {
                let first = try XCTUnwrap(stroke.path.first).location.applying(stroke.transform)
                let last = try XCTUnwrap(stroke.path.last).location.applying(stroke.transform)
                XCTAssertEqual(first.y, last.y, accuracy: 0.2, "Every synthetic line must actually be horizontal")
            }
            await model.performUndo()
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original)); XCTAssertFalse(model.canUndo)
            XCTAssertEqual(model.page?.recognizedText, header.recognizedText)
            await model.performRedo(); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, modified))
        }
    }
    @MainActor func testCancelAndPageNavigationDiscardPreviewWithoutEditingOrSavingTheSource() async throws {
        try await fixture { model in
            let original = model.canvas.drawing, source = try XCTUnwrap(model.page)
            model.beginHandwriting(.cleanup); _ = try await self.ready(model)
            model.cancelHandwriting()
            XCTAssertTrue(NativeInkComparison.equal(original, model.canvas.drawing)); XCTAssertFalse(model.dirty); XCTAssertFalse(model.canUndo)
            model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(original.strokes.indices)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            let second = try await model.workspace.addPage()
            await model.select(second)
            XCTAssertNil(model.handwriting); XCTAssertEqual(model.page?.id, second.id); XCTAssertFalse(session.canApply)
            session.apply(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            let stored = try await model.workspace.pageSnapshot(source.id)
            XCTAssertEqual(stored.drawingFile, source.drawingFile); XCTAssertEqual(stored.recognizedText, source.recognizedText)
        }
    }
    @MainActor func testLayerOwnerAndItsOtherNativeArchiveRemainUnchangedUntilApplyAndThroughUndo() async throws {
        try await fixture { model in
            let base = model.canvas.drawing
            let original = try XCTUnwrap(model.page)
            let added = try PageLayerEditing.adding(to: original, name: "Grafia")
            var layered = added.page; layered.revision += 1
            layered = try await model.workspace.save(layered, drawing: base.dataRepresentation(), layerID: added.layerID)
            try await model.load(layered); await model.selectLayer(added.layerID)
            model.tool = .objects; model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(base.strokes.indices)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            session.apply(); XCTAssertEqual(model.drawingLayerID, added.layerID)
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let stored = try await model.workspace.pageSnapshot(original.id)
            let baseRead = try await LayerDrawingReader.read(page: stored, layerID: original.id, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(baseRead.drawing, base))
            await model.performUndo(); XCTAssertEqual(model.drawingLayerID, added.layerID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
        }
    }
}
