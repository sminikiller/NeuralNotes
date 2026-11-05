import XCTest
@testable import NeuralNotesCore

final class LayerPackageFormatTests: XCTestCase {
    private func fixture(_ body: (NativeDocumentStore, DocumentWorkspace, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let package = store.packageURL(for: manifest.documentID)
        let workspace = DocumentWorkspace(package: package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        try await body(store, workspace, package)
    }
    private func decoded(_ path: String, package: URL) throws -> DocumentManifest {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DocumentManifest.self, from: Data(contentsOf: package.appendingPathComponent(path)))
    }
    private func bytes(_ value: DocumentManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    func testLegacyStaysVersionOneUntilTheFirstLayerHeaderAndItsInkIsNotMigrated() async throws {
        try await fixture { store, workspace, package in
            var page = try await workspace.addPage(); page.revision += 1
            page = try await workspace.save(page, drawing: Data([10, 20]))
            XCTAssertEqual(try self.decoded("manifest.json", package: package).schemaVersion, 1)
            let drawing = try XCTUnwrap(page.drawingFile)
            let added = try PageLayerEditing.adding(to: page, name: "Notes")
            XCTAssertEqual(try self.decoded("manifest.json", package: package).schemaVersion, 1, "Preparing UI metadata must not change a legacy notebook")
            page = try await workspace.saveLayerMetadata(added.page, expectedRevision: page.revision)
            XCTAssertEqual(try self.decoded("manifest.json", package: package).schemaVersion, 2)
            XCTAssertEqual(try self.decoded("manifest.previous.json", package: package).schemaVersion, 2)
            XCTAssertEqual(page.drawingFile, drawing)
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(drawing)), Data([10, 20]))
            let manifest = try await workspace.manifest()
            XCTAssertEqual(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID).schemaVersion, 2)
            XCTAssertNoThrow(try NativePackageInspector.inspect(package))
        }
    }

    func testAddingAnAlreadyLayeredPageCannotPublishItsStaleVersionOneOrderOverVersionTwo() async throws {
        try await fixture { _, workspace, package in
            let first = try await workspace.addPage()
            let layered = try PageLayerEditing.adding(to: PageSnapshot(), name: "Prepared notes")
            let added = try await workspace.addPage(layered.page)
            let manifest = try await workspace.manifest()
            XCTAssertEqual(manifest.schemaVersion, 2); XCTAssertEqual(manifest.pageIDs, [first.id, added.id])
            XCTAssertEqual(try self.decoded("manifest.previous.json", package: package).schemaVersion, 2)
        }
    }

    func testUnknownFutureRecoveryHeaderIsNeverOverwrittenByALayerPromotion() async throws {
        try await fixture { _, workspace, package in
            let page = try await workspace.addPage()
            let future = Data(#"{"schemaVersion":99}"#.utf8)
            try future.write(to: package.appendingPathComponent("manifest.previous.json"), options: .atomic)
            let added = try PageLayerEditing.adding(to: page, name: "Not committed")
            do {
                _ = try await workspace.saveLayerMetadata(added.page, expectedRevision: page.revision)
                XCTFail("The future recovery header must be retained")
            } catch LibraryFailure.unsupportedVersion(let version) { XCTAssertEqual(version, 99) }
            let stored = try await workspace.pageSnapshot(page.id)
            XCTAssertNil(stored.layers)
            XCTAssertEqual(try self.decoded("manifest.json", package: package).schemaVersion, 1)
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("manifest.previous.json")), future)
        }
    }

    func testCrashAfterOnlyTheMainManifestPromotionProtectsItsBackupBeforePublishingLayers() async throws {
        try await fixture { _, workspace, package in
            let page = try await workspace.addPage(), initial = try await workspace.manifest()
            try self.bytes(initial).write(to: package.appendingPathComponent("manifest.previous.json"), options: .atomic)
            try self.bytes(initial.retainingFormat(atLeast: 2)).write(to: package.appendingPathComponent("manifest.json"), options: .atomic)
            let resumed = DocumentWorkspace(package: package, documentID: initial.documentID, notebookID: initial.notebookID)
            let added = try PageLayerEditing.adding(to: page, name: "After crash")
            _ = try await resumed.saveLayerMetadata(added.page, expectedRevision: page.revision)
            XCTAssertEqual(try self.decoded("manifest.previous.json", package: package).schemaVersion, 2)
            let stored = try await resumed.pageSnapshot(page.id)
            XCTAssertEqual(stored.layers?.count, 2)
        }
    }

    func testCorruptMainAndOldRecoveryOrderCannotDowngradeRetainedLayeredPages() async throws {
        try await fixture { store, workspace, package in
            let first = try await workspace.addPage(), legacy = try await workspace.manifest()
            let layered = try PageLayerEditing.adding(to: PageSnapshot(), name: "Retained notes")
            let removed = try await workspace.addPage(layered.page)
            try await workspace.deletePage(removed.id)
            try self.bytes(legacy).write(to: package.appendingPathComponent("manifest.previous.json"), options: .atomic)
            try Data("interrupted".utf8).write(to: package.appendingPathComponent("manifest.json"), options: .atomic)
            try store.restorePreviousManifest(documentID: legacy.documentID, notebookID: legacy.notebookID)
            let restored = try store.read(documentID: legacy.documentID, notebookID: legacy.notebookID)
            XCTAssertEqual(restored.schemaVersion, 2); XCTAssertEqual(restored.pageIDs, [first.id])
            XCTAssertEqual(try self.decoded("manifest.previous.json", package: package).schemaVersion, 2)
            let retained = try await workspace.retainedPageSnapshot(removed.id)
            XCTAssertEqual(retained?.layers?.count, 2)
        }
    }

    func testCloningAndUndoOfTheFirstLayerKeepTheMonotonicFormatAndOriginalBytes() async throws {
        try await fixture { store, workspace, package in
            var page = try await workspace.addPage(); page.revision += 1
            page = try await workspace.save(page, drawing: Data([77]))
            let initial = try await workspace.manifest()
            let legacyCopy = UUID(), legacyNotebook = UUID()
            try store.clone(from: package, documentID: legacyCopy, notebookID: legacyNotebook)
            XCTAssertEqual(try store.read(documentID: legacyCopy, notebookID: legacyNotebook).schemaVersion, 1)
            let before = try PageEditSnapshotBuilder(documentID: initial.documentID, parent: package.deletingLastPathComponent().appendingPathComponent("history"), preservingBaseReferences: true)
            try await before.append(page, drawing: nil, sourcePackage: package)
            let snapshot = try await before.finish()
            let added = try PageLayerEditing.adding(to: page, name: "Notes")
            let saved = try await workspace.saveLayerMetadata(added.page, expectedRevision: page.revision)
            let layerCopy = UUID(), layerNotebook = UUID()
            try store.clone(from: package, documentID: layerCopy, notebookID: layerNotebook)
            XCTAssertEqual(try store.read(documentID: layerCopy, notebookID: layerNotebook).schemaVersion, 2)
            XCTAssertNoThrow(try NativePackageInspector.inspect(store.packageURL(for: layerCopy)))
            try await workspace.applyPageEdit(snapshot, expectedOrder: [page.id], newOrder: [page.id], expectedRevisions: [page.id: saved.revision])
            let restored = try await workspace.pageSnapshot(page.id), manifest = try await workspace.manifest()
            XCTAssertNil(restored.layers); XCTAssertEqual(manifest.schemaVersion, 2)
            XCTAssertEqual(restored.drawingFile, page.drawingFile)
            let data = try await workspace.drawing(restored); XCTAssertEqual(data, Data([77]))
        }
    }
}
