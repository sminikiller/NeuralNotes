import XCTest
@testable import NeuralNotesCore

final class PageLayerFoundationTests: XCTestCase {
    func testLegacyPageHasAnImplicitBaseWithoutRewritingItsDrawingOrEncodingNewKeys() throws {
        var page = PageSnapshot(); page.drawingFile = "drawings/base.drawing"; page.previousDrawingFile = "drawings/old.drawing"
        page.texts = [TextElement(text: "Conservato")]
        let bytes = try JSONEncoder().encode(page), reopened = try JSONDecoder().decode(PageSnapshot.self, from: bytes)
        XCTAssertEqual(reopened, page); XCTAssertNil(reopened.layers)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("layerID"))
        XCTAssertEqual(PageLayers.ordered(in: reopened).map(\.id), [page.id])
        XCTAssertTrue(PageLayers.editable(page.id, page: reopened))
        XCTAssertEqual(reopened.mediaFiles, ["drawings/base.drawing", "drawings/old.drawing"])
        try PageValidation.validate(reopened)
    }
    func testHiddenAndLockedLayersStillProtectEveryCurrentAndPreviousMediaFile() throws {
        var page = PageSnapshot(); var layer = PageLayer(name: "Annotazioni", isVisible: false, isLocked: true)
        layer.drawingFile = "drawings/notes.drawing"; layer.previousDrawingFile = "drawings/notes-old.drawing"
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]
        page.drawingFile = "drawings/base.drawing"; page.pdfFile = "attachments/source.pdf"
        var text = TextElement(text: "In alto"); text.layerID = layer.id; page.texts = [text]
        XCTAssertFalse(PageLayers.editable(layer.id, page: page)); try PageValidation.validate(page)
        XCTAssertEqual(page.mediaFiles, ["drawings/base.drawing", "drawings/notes.drawing", "drawings/notes-old.drawing", "attachments/source.pdf"])
        XCTAssertEqual(page.snapshotMediaFiles, ["drawings/notes.drawing", "drawings/notes-old.drawing"])
        page.remapMedia { $0.replacingOccurrences(of: "drawings/", with: "drawings/import/") }
        XCTAssertEqual(page.layers?.last?.drawingFile, "drawings/import/notes.drawing")
    }
    func testValidationRejectsMissingBaseDuplicateIDsBadPathsDanglingOwnershipAndInvalidOpacity() throws {
        let original = PageSnapshot(); var page = original
        page.layers = []; XCTAssertThrowsError(try PageValidation.validate(page))
        page.layers = [PageLayer(name: "Missing")]; XCTAssertThrowsError(try PageValidation.validate(page))
        page.layers = [PageLayer(id: page.id, name: "Base"), PageLayer(id: page.id, name: "Duplicate")]
        XCTAssertThrowsError(try PageValidation.validate(page))
        page = original; var layer = PageLayer(name: "Bad"); layer.drawingFile = "drawings/../other.drawing"
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]; XCTAssertThrowsError(try PageValidation.validate(page))
        layer.drawingFile = "drawings/good.drawing"; layer.opacity = .nan
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]; XCTAssertThrowsError(try PageValidation.validate(page))
        page = original; var text = TextElement(text: "Dangling"); text.layerID = UUID(); page.texts = [text]
        XCTAssertThrowsError(try PageValidation.validate(page))
        page = original; page.layers = [PageLayer(id: page.id, name: "Base")] + (0..<16).map { PageLayer(name: "\($0)") }
        XCTAssertThrowsError(try PageValidation.validate(page))
    }
    func testToolEligibilityAndExportUseOneScopeWithoutChangingHiddenContent() throws {
        var page = PageSnapshot(); let base = PageLayer(id: page.id, name: "Base")
        let hidden = PageLayer(name: "Hidden", isVisible: false), locked = PageLayer(name: "Locked", isLocked: true), active = PageLayer(name: "Active")
        page.layers = [hidden, active, base, locked] // Base can be above another layer.
        var a = TextElement(text: "A"); a.layerID = active.id
        var b = TextElement(text: "B"); b.layerID = hidden.id
        var c = TextElement(text: "C"); c.layerID = locked.id
        let normal = TextElement(text: "Base"); page.texts = [a, b, c, normal]; page.lockedObjects = [a.id]
        var mark = PDFMarkup(kind: .highlight, x: 10, y: 10, width: 10, height: 10, text: "word"); mark.layerID = active.id; page.pdfMarkups = [mark]
        let original = page
        XCTAssertEqual(PageLayers.ownedObjectIDs(in: page, layerID: active.id), [a.id])
        XCTAssertEqual(PageLayers.editableObjectIDs(in: page, layerID: active.id), [])
        XCTAssertEqual(PageLayers.editableObjectIDs(in: page, layerID: hidden.id), [])
        XCTAssertEqual(PageLayers.editableObjectIDs(in: page, layerID: locked.id), [])
        XCTAssertEqual(PageLayers.editableObjectIDs(in: page, layerID: page.id), [normal.id])
        XCTAssertEqual(PageLayers.editableMarkupIDs(in: page, layerID: active.id), [mark.id])
        XCTAssertEqual(LayerExportSelection.all.layers(in: page).map(\.id), [hidden.id, active.id, base.id, locked.id])
        XCTAssertEqual(LayerExportSelection.visible.layers(in: page).map(\.id), [active.id, base.id, locked.id])
        XCTAssertEqual(LayerExportSelection.selected([hidden.id]).layers(in: page).map(\.id), [hidden.id])
        XCTAssertEqual(page, original); try PageValidation.validate(page)
    }
    func testCopiedNativeSignaturesAreSeparatedByLayerAndLegacyNilStillMeansBase() {
        let page = UUID(), other = UUID(), signature = "same-native-path-and-date"
        let legacy = LayerInkSignature(layerID: nil, pageID: page, signature: signature)
        let explicitBase = LayerInkSignature(layerID: page, pageID: page, signature: signature)
        let copied = LayerInkSignature(layerID: other, pageID: page, signature: signature)
        XCTAssertEqual(legacy, explicitBase); XCTAssertNotEqual(legacy, copied)
        XCTAssertEqual(Set([legacy, explicitBase, copied]).count, 2)
    }
    func testMaintenanceInspectorAndUndoSnapshotRetainHiddenLayerFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(), layer = PageLayer(name: "Hidden", isVisible: false, isLocked: true)
        layer.drawingFile = "drawings/hidden.drawing"; layer.previousDrawingFile = "drawings/hidden-old.drawing"
        let current = package.appendingPathComponent(layer.drawingFile!), previous = package.appendingPathComponent(layer.previousDrawingFile!)
        try Data([1, 2, 3]).write(to: current); try Data([4, 5]).write(to: previous)
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]
        page.revision += 1
        page = try await workspace.save(page, drawing: Data([6]))
        let report = try await workspace.storageReport()
        XCTAssertFalse(report.unusedFiles.contains(layer.drawingFile!)); XCTAssertFalse(report.unusedFiles.contains(layer.previousDrawingFile!))
        XCTAssertNoThrow(try NativePackageInspector.inspect(package))
        let builder = try PageEditSnapshotBuilder(documentID: manifest.documentID, parent: root.appendingPathComponent("undo"))
        try await builder.append(page, drawing: Data([6]), sourcePackage: package)
        let snapshot = try await builder.finish()
        try FileManager.default.removeItem(at: current); try FileManager.default.removeItem(at: previous)
        XCTAssertThrowsError(try NativePackageInspector.inspect(package))
        try snapshot.restoreMedia(in: package)
        XCTAssertEqual(try Data(contentsOf: current), Data([1, 2, 3])); XCTAssertEqual(try Data(contentsOf: previous), Data([4, 5]))
        XCTAssertNoThrow(try NativePackageInspector.inspect(package)); XCTAssertEqual(try snapshot.page(page.id).layers, page.layers)
    }
    func testPageCloneRenewsLayerAndObjectOwnershipTogetherIncludingAudio() throws {
        var page = PageSnapshot(); let old = page.id, layer = PageLayer(name: "Notes")
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]
        var text = TextElement(text: "x"); text.layerID = layer.id; page.texts = [text]
        var anchor = StrokeAnchor(signature: "s", audioSessionID: UUID(), seconds: 10); anchor.layerID = layer.id; page.anchors = [anchor]
        page.id = UUID(); page.renewLayerIDs(from: old)
        XCTAssertEqual(page.layers?.first?.id, page.id); XCTAssertNotEqual(page.layers?.last?.id, layer.id)
        XCTAssertEqual(page.texts.first?.layerID, page.layers?.last?.id); XCTAssertEqual(page.anchors.first?.layerID, page.layers?.last?.id)
        XCTAssertEqual(page.anchors.first?.seconds, 10); try PageValidation.validate(page)
    }
    func testRepeatedSavesRetainSharedLayerInkAndTrashButBoundUnreferencedRevisions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var first = try await workspace.addPage()
        first.revision += 1; first = try await workspace.save(first, drawing: Data([1]))
        let shared = try XCTUnwrap(first.drawingFile)
        var second = PageSnapshot(), layer = PageLayer(name: "Shared hidden ink", isVisible: false, isLocked: true)
        layer.drawingFile = shared; second.layers = [PageLayer(id: second.id, name: "Base"), layer]
        second = try await workspace.addPage(second)
        try await workspace.deletePage(second.id) // Trash is still a durable owner.
        for revision in 2...40 {
            first.revision += 1; first = try await workspace.save(first, drawing: Data([UInt8(revision)]))
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(shared)), Data([1]))
        }
        let files = try FileManager.default.contentsOfDirectory(at: package.appendingPathComponent("drawings"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3, "Two live revisions plus the shared, hidden, trashed layer; no per-stroke accumulation")
        let report = try await workspace.storageReport(); XCTAssertFalse(report.unusedFiles.contains(shared))
        try await workspace.permanentlyRemovePages([second.id])
        let unowned = try await workspace.storageReport(); XCTAssertTrue(unowned.unusedFiles.contains(shared))
        _ = try await workspace.cleanUnusedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent(shared).path))
    }
    func testUnparseableHeaderNeverAuthorizesReleasingAnOldDrawing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage()
        page.revision += 1; page = try await workspace.save(page, drawing: Data([1]))
        let first = try XCTUnwrap(page.drawingFile)
        try Data("unreadable header".utf8).write(to: package.appendingPathComponent("pages/\(UUID()).json"))
        for revision in 2...4 { page.revision += 1; page = try await workspace.save(page, drawing: Data([UInt8(revision)])) }
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(first)), Data([1]))
        let report = try await workspace.storageReport(); XCTAssertFalse(report.unreadableHeaders.isEmpty)
    }

    func testLayerDrawingSaveCommitsOnlyItsPointerAndKeepsTwoRevisionsPerOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); let layer = PageLayer(name: "Annotazioni")
        page.layers = [PageLayer(id: page.id, name: "Base"), layer]
        for n in 1...12 {
            page.revision += 1; page = try await workspace.save(page, drawing: Data([UInt8(n)]))
            let base = page.drawingFile
            page.revision += 1; page = try await workspace.save(page, drawing: Data([UInt8(100 + n)]), layerID: layer.id)
            XCTAssertEqual(page.drawingFile, base)
            let baseData = try await workspace.drawing(page), layerData = try await workspace.drawing(page, layerID: layer.id)
            XCTAssertEqual(baseData, Data([UInt8(n)])); XCTAssertEqual(layerData, Data([UInt8(100 + n)]))
        }
        let count = try FileManager.default.contentsOfDirectory(at: package.appendingPathComponent("drawings"), includingPropertiesForKeys: nil).count
        XCTAssertEqual(count, 4)
        XCTAssertNoThrow(try NativePackageInspector.inspect(package))
        let original = page
        page.layers?[1].isLocked = true; page.revision += 1
        do { _ = try await workspace.save(page, drawing: Data([99]), layerID: layer.id); XCTFail("Locked layer accepted live ink") }
        catch { XCTAssertTrue(error is WorkspaceFailure) }
        let retained = try await workspace.pageSnapshot(page.id); XCTAssertEqual(retained, original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: package.appendingPathComponent("drawings"), includingPropertiesForKeys: nil).count, 4)
    }

    func testCloningAnImplicitBaseRemapsExplicitBaseOwnersWithoutMaterializingLayers() throws {
        var page = PageSnapshot(); let previous = page.id
        var text = TextElement(text: "Explicit base"); text.layerID = previous; page.texts = [text]
        var anchor = StrokeAnchor(signature: "base", audioSessionID: UUID(), seconds: 2); anchor.layerID = previous; page.anchors = [anchor]
        try PageValidation.validate(page)
        page.id = UUID(); page.renewLayerIDs(from: previous)
        XCTAssertNil(page.layers); XCTAssertEqual(page.texts.first?.layerID, page.id); XCTAssertEqual(page.anchors.first?.layerID, page.id)
        try PageValidation.validate(page)
    }

}
