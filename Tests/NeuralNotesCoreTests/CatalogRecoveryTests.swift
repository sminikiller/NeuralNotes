import Foundation
import XCTest
@testable import NeuralNotesCore

final class CatalogRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentManifest, DocumentWorkspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        return (root, store, manifest, workspace)
    }
    private func seed(_ workspace: DocumentWorkspace) async throws -> NotebookWorkspaces {
        let settings = NotebookWorkspaces.starter()
        try await workspace.setEditorWorkspaces(settings)
        try await workspace.setCoverAppearance(image: nil, design: CoverDesign())
        return settings
    }
    func testRecoveryPreservesBrokenBytesAllMediaAndPageInk() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([1, 2, 3]))
        let settings = try await seed(workspace)
        let orphan = try await workspace.url("audio/unindexed.caf"); try Data([7, 8]).write(to: orphan)
        let current = try await workspace.url("catalog.json"), broken = Data("interrupted catalog".utf8)
        try broken.write(to: current)
        let status = try await workspace.catalogRecoveryStatus(); XCTAssertTrue(status.needsRecovery); XCTAssertTrue(status.canRestore)
        try await workspace.restorePreviousCatalog()
        let restored = try await workspace.catalog(); XCTAssertEqual(restored.editorWorkspaces, settings)
        let ink = try await workspace.drawing(page); XCTAssertEqual(ink, Data([1, 2, 3]))
        let directory = try await workspace.url("recovery")
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("catalog-interrupted-") }
        XCTAssertEqual(copies.count, 1); XCTAssertEqual(try Data(contentsOf: copies[0]), broken)
        _ = try await workspace.cleanUnusedFiles(); XCTAssertEqual(try Data(contentsOf: orphan), Data([7, 8]))
    }
    func testMissingCatalogWithPreviousCopyCannotBecomeAnEmptyCatalog() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = try await seed(workspace)
        let current = try await workspace.url("catalog.json"); try FileManager.default.removeItem(at: current)
        do { _ = try await workspace.catalog(); XCTFail("Missing catalog became empty") } catch LibraryFailure.recoveryRequired { }
        try await workspace.restorePreviousCatalog()
        let catalog = try await workspace.catalog(); XCTAssertEqual(catalog.editorWorkspaces, settings)
    }
    func testRecoveryRefusesFutureSchemaAndKeepsSourceUntouched() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await seed(workspace)
        let current = try await workspace.url("catalog.json"), future = Data(#"{"schemaVersion":99}"#.utf8)
        try future.write(to: current)
        do { try await workspace.restorePreviousCatalog(); XCTFail("New schema rolled back") }
        catch LibraryFailure.unsupportedVersion(99) { }
        XCTAssertEqual(try Data(contentsOf: current), future)
    }
    func testCleanupProtectsMediaReferencedOnlyByPreviousCatalog() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await workspace.setCoverImage(Data([1, 2, 3]))
        let catalog = try await workspace.catalog()
        let old = try XCTUnwrap(catalog.coverImageFile)
        try await workspace.setCoverImage(Data([4, 5, 6]))
        _ = try await workspace.cleanUnusedFiles()
        let file = try await workspace.url(old); XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
    }
    func testMissingPreviousMediaPreventsRecoveryWithoutChangingCurrentBytes() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try await workspace.setCoverImage(Data([1]))
        let catalog = try await workspace.catalog(), file = try await workspace.url(try XCTUnwrap(catalog.coverImageFile))
        try await workspace.setCoverImage(nil); try FileManager.default.removeItem(at: file)
        let current = try await workspace.url("catalog.json"), broken = Data("broken".utf8); try broken.write(to: current)
        let status = try await workspace.catalogRecoveryStatus(); XCTAssertFalse(status.canRestore)
        do { try await workspace.restorePreviousCatalog(); XCTFail("Missing media accepted") } catch { }
        XCTAssertEqual(try Data(contentsOf: current), broken)
    }
    func testBackupRestoreRefreshesRecoveryCatalogWithNewIdentities() async throws {
        let (root, store, manifest, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        try await workspace.saveSession(AudioSession(title: "Lezione recuperabile")); _ = try await seed(workspace)
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Recupero", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let archive = try await workspace.exportNative(metadata: metadata)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let id = UUID(), notebookID = UUID()
        _ = try NativeImport.copy(from: archive, into: store, documentID: id, notebookID: notebookID)
        let copy = DocumentWorkspace(package: store.packageURL(for: id), documentID: id, notebookID: notebookID)
        let catalog = try await copy.catalog(), source = try await workspace.catalog()
        XCTAssertNotEqual(catalog.sessions.first?.id, source.sessions.first?.id)
        let current = try await copy.url("catalog.json"); try Data("broken".utf8).write(to: current)
        try await copy.restorePreviousCatalog()
        let recovered = try await copy.catalog(); XCTAssertEqual(recovered.sessions.first?.id, catalog.sessions.first?.id)
    }
}
