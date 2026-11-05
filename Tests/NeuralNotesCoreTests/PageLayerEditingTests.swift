import XCTest
@testable import NeuralNotesCore

final class PageLayerEditingTests: XCTestCase {
    func testClearingBaseRetainsPDFAndOtherOwnersAndDetachesTheirDeletedTargets() throws {
        var page = PageSnapshot(); page.pdfFile = "pdf/source.pdf"; page.pdfIndex = 0
        page.drawingFile = "drawings/base.drawing"; page.previousDrawingFile = "drawings/base-previous.drawing"
        let added = try PageLayerEditing.adding(to: page, name: "Keep"); page = added.page
        page.layers?[1].drawingFile = "drawings/upper.drawing"
        let base = TextElement(text: "Base")
        var explicitBase = TextElement(text: "Explicit Base"); explicitBase.layerID = page.id
        var upper = TextElement(text: "Upper"); upper.layerID = added.layerID
        page.texts = [base, explicitBase, upper]
        var edge = ConnectorElement(from: .init(objectID: base.id, x: 60, y: 90), to: .init(objectID: upper.id, x: 80, y: 100))
        edge.layerID = added.layerID; page.connectors = [edge]
        page.lockedObjects = [base.id, upper.id]; page.aboveInkObjects = [base.id, upper.id]
        let original = page
        let cleared = try PageLayerEditing.clearing(page.id, in: page)
        XCTAssertEqual(cleared.pdfFile, original.pdfFile); XCTAssertEqual(cleared.pdfIndex, original.pdfIndex)
        XCTAssertEqual(cleared.layers, original.layers)
        XCTAssertNil(cleared.drawingFile); XCTAssertNil(cleared.previousDrawingFile)
        XCTAssertEqual(cleared.texts.map(\.id), [upper.id])
        XCTAssertEqual(cleared.connectors?.first?.from.objectID, nil)
        XCTAssertEqual(cleared.connectors?.first?.to.objectID, upper.id)
        XCTAssertEqual(cleared.lockedObjects, [upper.id]); XCTAssertEqual(cleared.aboveInkObjects, [upper.id])
        XCTAssertEqual(page, original); try PageValidation.validate(cleared)
        let locked = try PageLayerEditing.lock(page.id, locked: true, in: page)
        XCTAssertThrowsError(try PageLayerEditing.clearing(page.id, in: locked))
        let emptyUpper = try PageLayerEditing.clearing(added.layerID, in: page)
        XCTAssertEqual(emptyUpper.drawingFile, page.drawingFile)
        XCTAssertNil(emptyUpper.layers?[1].drawingFile)
        XCTAssertEqual(emptyUpper.texts.map(\.id), [base.id, explicitBase.id])
    }

    func testInFlightPointerRebasePreservesNewLayerMetadataAndDoesNotCrossPages() throws {
        let added = try PageLayerEditing.adding(to: PageSnapshot(), name: "Notes")
        var saved = added.page; saved.revision = 7; saved.lastEditedAt = 123
        saved.drawingFile = "drawings/base-new.drawing"; saved.previousDrawingFile = "drawings/base-old.drawing"
        saved.layers?[1].drawingFile = "drawings/notes-new.drawing"
        saved.layers?[1].previousDrawingFile = "drawings/notes-old.drawing"
        var pending = try PageLayerEditing.renaming(added.layerID, to: "Renamed while saving", in: added.page)
        pending = try PageLayerEditing.opacity(added.layerID, value: 0.4, in: pending)
        let extra = try PageLayerEditing.adding(to: pending, name: "Created while saving")
        let rebased = PageLayers.rebasingDrawingReferences(extra.page, from: saved)
        XCTAssertEqual(rebased.revision, 7); XCTAssertEqual(rebased.lastEditedAt, 123)
        XCTAssertEqual(rebased.drawingFile, saved.drawingFile)
        XCTAssertEqual(rebased.layers?[1].drawingFile, saved.layers?[1].drawingFile)
        XCTAssertEqual(rebased.layers?[1].previousDrawingFile, saved.layers?[1].previousDrawingFile)
        XCTAssertEqual(rebased.layers?[1].name, "Renamed while saving"); XCTAssertEqual(rebased.layers?[1].opacity, 0.4)
        XCTAssertEqual(rebased.layers?.last?.id, extra.layerID)
        let other = PageSnapshot()
        XCTAssertEqual(PageLayers.rebasingDrawingReferences(other, from: saved), other)
        try PageValidation.validate(rebased)
    }

    func testMetadataEditingKeepsAllContentAndUsesCanonicalOrderAndBounds() throws {
        var original = PageSnapshot(); original.drawingFile = "drawings/base.drawing"; original.texts = [TextElement(text: "Base retained")]
        let added = try PageLayerEditing.adding(to: original, name: "  Annotazioni  "), id = added.layerID
        var page = added.page
        XCTAssertEqual(page.layers?.map(\.name), ["Base", "Annotazioni"])
        page = try PageLayerEditing.renaming(id, to: "Matematica", in: page)
        page = try PageLayerEditing.opacity(id, value: 0.5, in: page)
        page = try PageLayerEditing.visibility(id, visible: false, in: page)
        page = try PageLayerEditing.lock(id, locked: true, in: page)
        page = try PageLayerEditing.reordering([id, page.id], in: page)
        XCTAssertEqual(page.layers?.first?.id, id); XCTAssertEqual(page.layers?.first?.opacity, 0.5)
        XCTAssertFalse(PageLayers.editable(id, page: page))
        XCTAssertEqual(page.texts, original.texts); XCTAssertEqual(page.drawingFile, original.drawingFile)
        XCTAssertThrowsError(try PageLayerEditing.reordering([id, id], in: page))
        XCTAssertThrowsError(try PageLayerEditing.opacity(id, value: .nan, in: page))
        XCTAssertThrowsError(try PageLayerEditing.opacity(id, value: 1.01, in: page))
        XCTAssertThrowsError(try PageLayerEditing.renaming(id, to: "  ", in: page))
        XCTAssertThrowsError(try PageLayerEditing.removing(id, in: page))
        XCTAssertThrowsError(try PageLayerEditing.removing(page.id, in: page))
        page = try PageLayerEditing.lock(id, locked: false, in: page)
        let removed = try PageLayerEditing.removing(id, in: page)
        XCTAssertEqual(removed.layers?.map(\.id), [page.id]); XCTAssertEqual(removed.texts, original.texts)
        while (page.layers?.count ?? 0) < 16 { page = try PageLayerEditing.adding(to: page, name: "Layer").page }
        XCTAssertThrowsError(try PageLayerEditing.adding(to: page, name: "Excess"))
        XCTAssertNil(original.layers); try PageValidation.validate(page)
    }
    func testDuplicateRemapsObjectsInternalEdgesAndAudioWithoutMutatingOrSharingNativeInk() throws {
        var page = PageSnapshot(); page.drawingFile = "drawings/base.drawing"
        var text = TextElement(text: "Inside"); let outside = TextElement(text: "Outside")
        let added = try PageLayerEditing.adding(to: page, name: "Notes"), id = added.layerID
        page = added.page; text.layerID = id; page.texts = [text, outside]
        var shape = ShapeElement(kind: .triangle, x: 100, y: 100, width: 100, height: 80); shape.layerID = id
        var anchor = StrokeAnchor(signature: "same-native-signature", audioSessionID: UUID(), seconds: 17.25); anchor.layerID = id
        shape.audioAnchor = anchor; page.shapes = [shape]; page.anchors = [anchor]
        var connector = ConnectorElement(from: .init(objectID: text.id, x: 60, y: 90), to: .init(objectID: shape.id, x: 140, y: 100))
        connector.layerID = id
        var external = ConnectorElement(from: .init(objectID: shape.id, x: 140, y: 100), to: .init(objectID: outside.id, x: 60, y: 64))
        external.layerID = id; page.connectors = [connector, external]
        page.layers?[1].drawingFile = "drawings/notes.drawing"
        page.aboveInkObjects = [shape.id]; page.lockedObjects = [text.id]
        let before = page
        XCTAssertThrowsError(try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: nil))
        XCTAssertThrowsError(try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: "drawings/notes.drawing"))
        let result = try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: "drawings/copy.drawing")
        let copiedText = try XCTUnwrap(result.page.texts.first(where: { $0.layerID == result.layerID }))
        let copiedShape = try XCTUnwrap(result.page.shapes?.first(where: { $0.layerID == result.layerID }))
        let edges = (result.page.connectors ?? []).filter { $0.layerID == result.layerID }
        XCTAssertEqual(edges[0].from.objectID, copiedText.id); XCTAssertEqual(edges[0].to.objectID, copiedShape.id)
        XCTAssertEqual(edges[1].from.objectID, copiedShape.id); XCTAssertEqual(edges[1].to.objectID, outside.id)
        XCTAssertEqual(result.page.layers?.map(\.id), [page.id, id, result.layerID])
        XCTAssertEqual(result.page.layers?.last?.drawingFile, "drawings/copy.drawing")
        XCTAssertEqual(result.page.anchors.last?.signature, anchor.signature); XCTAssertEqual(result.page.anchors.last?.seconds, 17.25)
        XCTAssertEqual(result.page.anchors.last?.layerID, result.layerID); XCTAssertNotEqual(result.page.anchors.last?.id, anchor.id)
        XCTAssertEqual(copiedShape.audioAnchor?.layerID, result.layerID)
        XCTAssertTrue(result.page.aboveInkObjects?.contains(copiedShape.id) == true)
        XCTAssertTrue(result.page.lockedObjects?.contains(copiedText.id) == true)
        XCTAssertEqual(page, before); try PageValidation.validate(result.page)
        let removed = try PageLayerEditing.removing(id, in: result.page)
        XCTAssertFalse(removed.texts.contains { $0.id == text.id }); XCTAssertTrue(removed.texts.contains { $0.id == copiedText.id })
        XCTAssertEqual(removed.anchors.count, 1); XCTAssertEqual(removed.anchors.first?.layerID, result.layerID)
        try PageValidation.validate(removed)
    }
    func testLayerHeaderCommitAndDuplicateRetainNativeBytesAndRejectAStaleOrMissingReference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision += 1
        let bytes = Data((0...255).map { UInt8($0) })
        page = try await workspace.save(page, drawing: bytes)
        let originalFile = try XCTUnwrap(page.drawingFile), original = page
        let added = try PageLayerEditing.adding(to: page, name: "Blank")
        page = try await workspace.saveLayerMetadata(added.page, expectedRevision: page.revision)
        XCTAssertEqual(page.drawingFile, originalFile); XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(originalFile)), bytes)
        do { _ = try await workspace.saveLayerMetadata(original, expectedRevision: original.revision); XCTFail("Stale header overwrote a newer layer") }
        catch { XCTAssertTrue(error is WorkspaceFailure) }
        let copy = try await workspace.duplicateLayer(pageID: page.id, layerID: page.id, name: "Base copy")
        let copiedFile = try XCTUnwrap(copy.page.layers?.first(where: { $0.id == copy.layerID })?.drawingFile)
        XCTAssertNotEqual(copiedFile, originalFile); XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(copiedFile)), bytes)
        let before = copy.page
        var invalid = before; invalid.layers?[1].drawingFile = "drawings/missing.drawing"
        do { _ = try await workspace.saveLayerMetadata(invalid, expectedRevision: before.revision); XCTFail("Missing vector reference was published") }
        catch {}
        let retained = try await workspace.pageSnapshot(page.id); XCTAssertEqual(retained, before)
        XCTAssertNoThrow(try NativePackageInspector.inspect(package))
        let removed = try PageLayerEditing.removing(copy.layerID, in: before)
        _ = try await workspace.saveLayerMetadata(removed, expectedRevision: before.revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent(copiedFile).path))
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(originalFile)), bytes)
    }

    func testFileBackedLayerHistoryRestoresEveryBaseAndLayerPointerAfterPackageCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID), workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage()
        let added = try PageLayerEditing.adding(to: page, name: "Notes"); page = added.page
        page.revision += 1; page = try await workspace.save(page, drawing: Data([10]))
        page.revision += 1; page = try await workspace.save(page, drawing: Data([20]), layerID: added.layerID)
        let before = page, baseFile = try XCTUnwrap(page.drawingFile), layerFile = try XCTUnwrap(page.layers?.last?.drawingFile)
        let builder = try PageEditSnapshotBuilder(documentID: manifest.documentID, parent: root.appendingPathComponent("undo"), preservingBaseReferences: true)
        try await builder.append(page, drawing: nil, sourcePackage: package)
        let saved = try await builder.finish()
        XCTAssertTrue(saved.preservesBaseReferences); XCTAssertNil(try saved.drawingURL(page.id))
        for revision in 1...4 {
            page.revision += 1; page = try await workspace.save(page, drawing: Data([UInt8(30 + revision)]))
            page.revision += 1; page = try await workspace.save(page, drawing: Data([UInt8(40 + revision)]), layerID: added.layerID)
        }
        _ = try await workspace.cleanUnusedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent(baseFile).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent(layerFile).path))
        try await workspace.applyPageEdit(saved, expectedOrder: [page.id], newOrder: [page.id], expectedRevisions: [page.id: page.revision])
        let restored = try await workspace.pageSnapshot(page.id)
        XCTAssertEqual(restored.drawingFile, before.drawingFile); XCTAssertEqual(restored.layers, before.layers)
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(baseFile)), Data([10]))
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(layerFile)), Data([20]))
        XCTAssertNoThrow(try NativePackageInspector.inspect(package))
    }

    func testStagingMultipleOwnersPublishesNoHeaderAndFileBackedCommitRestoresAllReferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision += 1
        page = try await workspace.save(page, drawing: Data([10]))
        let added = try PageLayerEditing.adding(to: page, name: "Upper"); page = added.page; page.revision += 1
        page = try await workspace.save(page, drawing: Data([20]), layerID: added.layerID)
        let beforeBuilder = try PageEditSnapshotBuilder(documentID: manifest.documentID, preservingBaseReferences: true)
        try await beforeBuilder.append(page, drawing: nil, sourcePackage: package)
        let before = try await beforeBuilder.finish()
        var staged = try await workspace.preparingLayerDrawing(Data([30]), in: page, layerID: page.id)
        staged = try await workspace.preparingLayerDrawing(Data([40]), in: staged, layerID: added.layerID)
        let unchanged = try await workspace.pageSnapshot(page.id); XCTAssertEqual(unchanged, page)
        let oldBase = try await workspace.drawing(page); XCTAssertEqual(oldBase, Data([10]))
        let oldUpper = try await workspace.drawing(page, layerID: added.layerID); XCTAssertEqual(oldUpper, Data([20]))
        let afterBuilder = try PageEditSnapshotBuilder(documentID: manifest.documentID, preservingBaseReferences: true)
        try await afterBuilder.append(staged, drawing: nil, sourcePackage: package)
        let after = try await afterBuilder.finish()
        try await workspace.applyPageEdit(after, expectedOrder: [page.id], newOrder: [page.id], expectedRevisions: [page.id: page.revision])
        let changed = try await workspace.pageSnapshot(page.id)
        let newBase = try await workspace.drawing(changed), newUpper = try await workspace.drawing(changed, layerID: added.layerID)
        XCTAssertEqual(newBase, Data([30])); XCTAssertEqual(newUpper, Data([40]))
        try await workspace.applyPageEdit(before, expectedOrder: [page.id], newOrder: [page.id], expectedRevisions: [page.id: changed.revision])
        let restored = try await workspace.pageSnapshot(page.id)
        XCTAssertEqual(restored.drawingFile, page.drawingFile); XCTAssertEqual(restored.layers, page.layers)
    }

}
