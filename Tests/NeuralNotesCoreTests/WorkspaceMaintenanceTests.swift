import XCTest
@testable import NeuralNotesCore

final class WorkspaceMaintenanceTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentManifest, DocumentWorkspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        return (root, store, manifest, DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
    }
    func testCleanupKeepsActivePreviousAndRemovedPageMedia() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([1])); page.revision = 2
        page = try await workspace.save(page, drawing: Data([2])); let retained = page
        try await workspace.deletePage(page.id)
        let extra = try await workspace.url("images/unused.png"); try Data([3, 4, 5]).write(to: extra)
        let freed = try await workspace.cleanUnusedFiles()
        XCTAssertEqual(freed, 3); XCTAssertFalse(FileManager.default.fileExists(atPath: extra.path))
        for path in [retained.drawingFile, retained.previousDrawingFile].compactMap({ $0 }) {
            let url = try await workspace.url(path); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        try await workspace.restoreRemovedPage(page.id)
        let pages = try await workspace.pages(); XCTAssertEqual(pages.map(\.id), [page.id])
    }
    func testMissingActiveHeaderBlocksCleanupAndPreservesUnknownReferences() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage()
        let header = try await workspace.url("pages/\(page.id).json"); try FileManager.default.removeItem(at: header)
        let file = try await workspace.url("images/possibly-referenced.png"); try Data([42]).write(to: file)
        do { _ = try await workspace.cleanUnusedFiles(); XCTFail("Unsafe cleanup accepted") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testPageOrderUndoUsesCompareAndSwapAndNeverPurgesActivePages() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try await workspace.addPage(), b = try await workspace.addPage()
        try await workspace.restorePageOrder([a.id], expected: [a.id, b.id])
        do { try await workspace.restorePageOrder([b.id], expected: [a.id, b.id]); XCTFail("Stale order accepted") } catch WorkspaceFailure.staleRevision { }
        do { try await workspace.permanentlyRemovePages([a.id]); XCTFail("Active page purged") } catch WorkspaceFailure.staleRevision { }
        try await workspace.restoreRemovedPage(b.id)
        let pages = try await workspace.pages(); XCTAssertEqual(pages.map(\.id), [a.id, b.id])
    }
    func testPreviousManifestCanBeRestoredWithoutLosingTheCorruptFile() async throws {
        let (root, store, manifest, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try await workspace.addPage(); _ = try await workspace.addPage()
        let file = try await workspace.url("manifest.json"); let corrupt = Data("interrupted".utf8)
        try corrupt.write(to: file)
        try store.restorePreviousManifest(documentID: manifest.documentID, notebookID: manifest.notebookID)
        XCTAssertEqual(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID).pageIDs, [a.id])
        let recovery = try await workspace.url("recovery")
        let copies = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        XCTAssertEqual(copies.count, 1); XCTAssertEqual(try Data(contentsOf: copies[0]), corrupt)
        let report = try await workspace.storageReport(); XCTAssertEqual(report.removedPages.count, 1)
    }
    func testRecoveryNeverRollsBackANewerFormat() async throws {
        let (root, store, manifest, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        let file = try await workspace.url("manifest.json")
        let newer = Data("{\"schemaVersion\":99}".utf8); try newer.write(to: file)
        XCTAssertThrowsError(try store.restorePreviousManifest(documentID: manifest.documentID, notebookID: manifest.notebookID))
        XCTAssertEqual(try Data(contentsOf: file), newer)
    }
}
