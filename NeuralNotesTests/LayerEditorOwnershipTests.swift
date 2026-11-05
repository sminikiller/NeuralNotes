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

    @MainActor func testLayerMetadataAndNativeInkShareOneChronologicalUndoAcrossOwnerChanges() async throws {
        try await fixture { model, _, base, _ in
            let pageID = try XCTUnwrap(model.page?.id)
            let added = await model.performLayerOperation(.add("New notes")); XCTAssertTrue(added)
            let owner = try XCTUnwrap(model.drawingLayerID)
            XCTAssertNotEqual(owner, pageID); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            let before = model.captureEdit(ink: true), ink = PKDrawing(strokes: [self.stroke(x: 340)])
            model.replaceInkSession(with: ink); model.recordEdit(before, label: "Inchiostro"); model.drawingChanged()
            let hidden = await model.performLayerOperation(.visibility(owner, false)); XCTAssertTrue(hidden)
            XCTAssertEqual(model.drawingLayerID, pageID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            await model.performUndo()
            XCTAssertEqual(model.drawingLayerID, owner)
            XCTAssertTrue(model.page?.layers?.first(where: { $0.id == owner })?.isVisible == true)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, ink))
            await model.performUndo()
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo()
            XCTAssertEqual(model.drawingLayerID, pageID)
            XCTAssertFalse(model.page?.layers?.contains(where: { $0.id == owner }) == true)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            await model.performRedo(); await model.performRedo()
            XCTAssertEqual(model.drawingLayerID, owner)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, ink))
        }
    }

    @MainActor func testTextCommitAndSelectionsStayOnTheirOwnerDuringAHandoff() async throws {
        try await fixture { model, layer, base, _ in
            let pageID = try XCTUnwrap(model.page?.id)
            model.addText()
            let baseText = try XCTUnwrap(model.selectedObjectID)
            await model.selectLayer(layer)
            model.selectAll(); XCTAssertFalse(model.selectedIDs.contains(baseText))
            model.selectedObjectID = baseText; XCTAssertNil(model.selectedObjectID)
            model.beginTextEdit(at: CGPoint(x: 300, y: 400))
            let textID = try XCTUnwrap(model.editingTextID)
            XCTAssertEqual(model.page?.texts.first(where: { $0.id == textID })?.layerID, layer)
            model.updateLiveText("Notes on upper layer")
            await model.selectLayer(pageID)
            XCTAssertNil(model.editingTextID); XCTAssertNil(model.textEditBefore)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            let stored = try await model.workspace.pageSnapshot(pageID)
            XCTAssertEqual(stored.texts.first(where: { $0.id == textID })?.text, "Notes on upper layer")
            await model.performUndo()
            XCTAssertEqual(model.drawingLayerID, layer)
            XCTAssertEqual(model.page?.texts.first(where: { $0.id == textID })?.text, "")
            XCTAssertTrue(model.page?.texts.contains(where: { $0.id == baseText }) == true)
        }
    }

    @MainActor func testDuplicateAndDeleteKeepIndependentNativeFilesAndUndoRestoresTheDeletedVectors() async throws {
        try await fixture { model, originalID, base, upper in
            await model.selectLayer(originalID)
            let sourceFile = try XCTUnwrap(PageLayers.drawingFile(for: originalID, in: XCTUnwrap(model.page)))
            let copied = await model.performLayerOperation(.duplicate(originalID, "Copy")); XCTAssertTrue(copied)
            let copyID = try XCTUnwrap(model.drawingLayerID)
            XCTAssertNotEqual(copyID, originalID)
            let copyFile = try XCTUnwrap(PageLayers.drawingFile(for: copyID, in: XCTUnwrap(model.page)))
            XCTAssertNotEqual(copyFile, sourceFile)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
            let before = model.captureEdit(ink: true)
            let edited = PKDrawing(strokes: upper.strokes + [self.stroke(x: 400)])
            model.replaceInkSession(with: edited); model.recordEdit(before, label: "Inchiostro"); model.drawingChanged()
            let removed = await model.performLayerOperation(.remove(copyID)); XCTAssertTrue(removed)
            XCTAssertFalse(model.page?.layers?.contains(where: { $0.id == copyID }) == true)
            await model.performUndo()
            XCTAssertEqual(model.drawingLayerID, copyID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, edited))
            let page = try XCTUnwrap(model.page)
            let source = try await LayerDrawingReader.read(page: page, layerID: originalID, workspace: model.workspace)
            let baseRead = try await LayerDrawingReader.read(page: page, layerID: page.id, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(source.drawing, upper))
            XCTAssertTrue(NativeInkComparison.equal(baseRead.drawing, base))
            XCTAssertEqual(PageLayers.drawingFile(for: originalID, in: page), sourceFile)
            await model.performUndo(); await model.performUndo()
            XCTAssertFalse(model.page?.layers?.contains(where: { $0.id == copyID }) == true)
            await model.performRedo()
            XCTAssertEqual(model.drawingLayerID, copyID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
        }
    }

    @MainActor func testDirectMetadataEditorsAndClipboardCannotModifyOrReassignAnotherOwnersObjects() async throws {
        try await fixture { model, owner, base, _ in
            model.mutatePage("Base text") { $0.texts.append(TextElement(text: "Base protected")) }
            let baseID = try XCTUnwrap(model.page?.texts.first?.id)
            await model.selectLayer(owner)
            model.mutatePage("Owner text") { $0.texts.append(TextElement(text: "Owner")) }
            let ownID = try XCTUnwrap(model.page?.texts.last?.id)
            XCTAssertEqual(model.page?.texts.last?.layerID, owner)
            let before = model.captureEdit()
            model.page?.texts.removeAll { $0.id == baseID }
            model.page?.texts.append(TextElement(text: "Inserted directly"))
            model.recordEdit(before, label: "Direct editor"); model.drawingChanged()
            XCTAssertEqual(model.page?.texts.first(where: { $0.id == baseID })?.text, "Base protected")
            XCTAssertEqual(model.page?.texts.last?.layerID, owner)
            model.selectedIDs = [ownID]; XCTAssertTrue(model.copySelection())
            await model.selectLayer(try XCTUnwrap(model.page?.id))
            await model.pasteSelection()
            let pasted = try XCTUnwrap(model.page?.texts.last)
            XCTAssertNotEqual(pasted.id, ownID); XCTAssertNil(pasted.layerID)
            XCTAssertEqual(model.page?.texts.first(where: { $0.id == ownID })?.layerID, owner)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
            try PageValidation.validate(try XCTUnwrap(model.page))
        }
    }

    @MainActor func testMovingUpperInkToAnotherPagePreservesBaseFilesAndCrossPageUndoRestoresItsOwner() async throws {
        try await fixture { model, owner, base, upper in
            let sourceID = try XCTUnwrap(model.page?.id)
            let destination = try await model.workspace.addPage()
            model.pages = try await model.workspace.pages()
            await model.selectLayer(owner)
            let baseFile = model.page?.drawingFile
            model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            await model.transferSelection(to: destination.id, copy: false)
            XCTAssertEqual(model.page?.id, destination.id)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let source = try await model.workspace.pageSnapshot(sourceID)
            XCTAssertEqual(source.drawingFile, baseFile)
            let sourceBase = try await LayerDrawingReader.read(page: source, layerID: sourceID, workspace: model.workspace)
            let sourceUpper = try await LayerDrawingReader.read(page: source, layerID: owner, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(sourceBase.drawing, base)); XCTAssertTrue(sourceUpper.drawing.strokes.isEmpty)
            await model.performUndo()
            XCTAssertEqual(model.page?.id, sourceID); XCTAssertEqual(model.drawingLayerID, owner)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
            let emptyDestination = try await model.workspace.pageSnapshot(destination.id)
            let restored = try await LayerDrawingReader.read(page: emptyDestination, layerID: destination.id, workspace: model.workspace)
            XCTAssertTrue(restored.drawing.strokes.isEmpty)
            await model.performRedo(); XCTAssertEqual(model.page?.id, destination.id)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].force, upper.strokes[0].path[0].force)
        }
    }

    @MainActor func testPaperResizeTransformsEveryOwnerAndUndoRestoresExactNativeInk() async throws {
        try await fixture { model, owner, base, upper in
            let page = try XCTUnwrap(model.page)
            await model.selectLayer(owner)
            var template = PageTemplate(); template.landscape = true
            let expected = template.makePage(), scale = min(expected.width / page.width, expected.height / page.height)
            let changed = await model.applyTemplate(template, useForNext: false); XCTAssertTrue(changed)
            let resized = try XCTUnwrap(model.page)
            let lower = try await LayerDrawingReader.read(page: resized, layerID: resized.id, workspace: model.workspace)
            let higher = try await LayerDrawingReader.read(page: resized, layerID: owner, workspace: model.workspace)
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            XCTAssertTrue(NativeInkComparison.equal(lower.drawing, base.transformed(using: transform)))
            XCTAssertTrue(NativeInkComparison.equal(higher.drawing, upper.transformed(using: transform)))
            await model.performUndo()
            XCTAssertEqual(model.page?.width, page.width); XCTAssertEqual(model.drawingLayerID, owner)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper))
            let old = try XCTUnwrap(model.page)
            let restored = try await LayerDrawingReader.read(page: old, layerID: old.id, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(restored.drawing, base))
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
