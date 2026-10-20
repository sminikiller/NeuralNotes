import XCTest
import SwiftData
import UIKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class LibraryPersistenceTests: XCTestCase {
    @MainActor
    func testPDFImportCreatesNotebookWithEditablePagesAndKeepsOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let source = root.appendingPathComponent("Lezione.pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
            context.beginPage(); context.beginPage()
        }
        try data.write(to: source)
        let notebook = try await repo.importNotebook(from: source, folderID: nil)
        XCTAssertEqual(notebook.title, "Lezione")
        let workspace = try repo.workspace(id: notebook.id)
        let pages = try await workspace.pages(); XCTAssertEqual(pages.count, 2); XCTAssertNotNil(pages[0].pdfFile)
        let editor = EditorViewModel(workspace: workspace); await editor.open(); editor.addText()
        let saved = await editor.close(); XCTAssertTrue(saved)
        let updated = try await workspace.pages(); XCTAssertEqual(updated[0].texts.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), data)
    }

    @MainActor
    func testInvalidPDFDoesNotEnterBackupImporterOrLeaveAnEmptyNotebook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let source = root.appendingPathComponent("Broken.pdf"), bytes = Data("broken PDF".utf8)
        try bytes.write(to: source)
        do { _ = try await repo.importNotebook(from: source, folderID: nil); XCTFail("Invalid PDF accepted") }
        catch { XCTAssertFalse(error is NativeArchiveFailure) }
        XCTAssertTrue(try repo.notebooks().isEmpty)
        let packages = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Notebooks"), includingPropertiesForKeys: nil)
        XCTAssertTrue(packages.isEmpty); XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    @MainActor
    func testEditorTouchDoesNotRevertARenameInAnotherWindow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let old = try repo.createNotebook(title: "Vecchio titolo", folderID: nil, cover: .lagoon)
        try repo.updateNotebook(id: old.id, title: "Nuovo titolo", folderID: nil, cover: .sand)
        let library = LibraryViewModel(repository: repo); library.didEdit(old)
        XCTAssertEqual(library.notebooks.first?.title, "Nuovo titolo")
        XCTAssertEqual(library.notebooks.first?.cover, .sand)
    }
    @MainActor
    private func repository(at root: URL) throws -> SwiftDataLibraryRepository {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let config = ModelConfiguration("Test", schema: schema,
            url: root.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                           configurations: [config])
        return SwiftDataLibraryRepository(container: container,
            documents: try NativeDocumentStore(root: root.appendingPathComponent("Notebooks")))
    }

    @MainActor
    func testCreateRenameAndReopenFromDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var first: SwiftDataLibraryRepository? = try repository(at: root)
        let notebook = try XCTUnwrap(first).createNotebook(title: "Fisica", folderID: nil, cover: .lagoon)
        try XCTUnwrap(first).updateNotebook(id: notebook.id, title: "Fisica II", folderID: nil, cover: .lavender)
        try XCTUnwrap(first).setFavorite(id: notebook.id, isFavorite: true)
        first = nil
        let reopened = try repository(at: root)
        let saved = try XCTUnwrap(reopened.notebooks().first)
        XCTAssertEqual(saved.id, notebook.id)
        XCTAssertEqual(saved.documentID, notebook.documentID)
        XCTAssertEqual(saved.title, "Fisica II")
        XCTAssertEqual(saved.cover, .lavender)
        XCTAssertTrue(saved.isFavorite)
        XCTAssertEqual(try reopened.openNotebook(id: saved.id).notebookID, saved.id)
        XCTAssertTrue(try reopened.integrityReport().isEmpty)
    }

    @MainActor
    func testFoldersDuplicationDeletionAndRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        try repo.createFolder(title: "Università", parentID: nil)
        let parent = try XCTUnwrap(repo.folders().first)
        try repo.createFolder(title: "Primo anno", parentID: parent.id)
        let child = try XCTUnwrap(repo.folders().first { $0.parentID == parent.id })
        let original = try repo.createNotebook(title: "Analisi", folderID: child.id, cover: .midnight)
        XCTAssertThrowsError(try repo.deleteFolder(id: parent.id))
        XCTAssertThrowsError(try repo.deleteFolder(id: child.id))
        let copy = try await repo.duplicateNotebook(id: original.id)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.documentID, original.documentID)
        XCTAssertEqual(copy.folderID, original.folderID)
        try repo.deleteNotebook(id: original.id)
        XCTAssertFalse(try repo.notebooks().contains { $0.id == original.id })
        try repo.restoreNotebook(id: original.id)
        XCTAssertNoThrow(try repo.openNotebook(id: original.id))
        try repo.deleteNotebook(id: original.id)
        try repo.deleteNotebook(id: copy.id)
        try repo.deleteFolder(id: child.id)
        try repo.deleteFolder(id: parent.id)
        try repo.restoreNotebook(id: original.id)
        XCTAssertNil(try repo.notebooks().first?.folderID)
        XCTAssertTrue(try repo.integrityReport().isEmpty)
    }

    @MainActor
    func testInvalidOperationsDoNotChangeSavedState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let notebook = try repo.createNotebook(title: "Storia", folderID: nil, cover: .sand)
        XCTAssertThrowsError(try repo.updateNotebook(id: notebook.id, title: "", folderID: nil, cover: .midnight))
        XCTAssertThrowsError(try repo.updateNotebook(id: notebook.id, title: "Altro", folderID: UUID(), cover: .midnight))
        XCTAssertEqual(try repo.notebooks().first?.title, "Storia")
        XCTAssertEqual(try repo.notebooks().count, 1)
    }

    @MainActor
    func testFailedManifestWriteLeavesNoNotebookRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let packages = root.appendingPathComponent("Notebooks")
        try FileManager.default.removeItem(at: packages)
        // Replace the parent directory with a file to simulate an IO failure reliably.
        try Data("blocked".utf8).write(to: packages)
        XCTAssertThrowsError(try repo.createNotebook(title: "Non salvato", folderID: nil, cover: .lagoon))
        XCTAssertTrue(try repo.notebooks().isEmpty)
    }

    @MainActor
    func testAnotherWindowCannotTrashAQuadernoWithAnActiveWriter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let notebook = try repo.createNotebook(title: "Aperto", folderID: nil, cover: .lagoon)
        let editor = EditorViewModel(workspace: try repo.workspace(id: notebook.id))
        await editor.open()
        XCTAssertTrue(editor.hasLease)
        XCTAssertThrowsError(try repo.deleteNotebook(id: notebook.id))
        XCTAssertEqual(try repo.notebooks().count, 1)
        _ = await editor.close()
        XCTAssertNoThrow(try repo.deleteNotebook(id: notebook.id))
        XCTAssertTrue(try repo.notebooks().isEmpty)
    }

    @MainActor
    func testMissingPackageIsReportedWithoutResettingMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try repository(at: root)
        let notebook = try repo.createNotebook(title: "Da recuperare", folderID: nil, cover: .lagoon)
        let store = try NativeDocumentStore(root: root.appendingPathComponent("Notebooks"))
        try store.removeUncommitted(documentID: notebook.documentID)
        XCTAssertEqual(try repo.integrityReport().count, 1)
        XCTAssertEqual(try repo.notebooks().count, 1)
        XCTAssertThrowsError(try repo.openNotebook(id: notebook.id))
    }
}
