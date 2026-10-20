import XCTest
@testable import NeuralNotesCore

final class NotebookSectionsTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentWorkspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), documentID = UUID(), notebookID = UUID()
        try store.create(DocumentManifest(documentID: documentID, notebookID: notebookID))
        return (root, store, DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID))
    }

    func testAssignmentsSurviveRenameDeleteUndoAndReopenWithoutTouchingInk() async throws {
        let (root, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1; page.texts = [TextElement(text: "Appunti originali")]
        page = try await workspace.save(page, drawing: Data([42, 15]))
        let section = NotebookSection(title: "Capitolo"), child = NotebookSection(title: "Esercizi")
        try await workspace.saveSection(section)
        var nested = child; nested.parentID = section.id; try await workspace.saveSection(nested)
        try await workspace.assignPages([page.id], toSection: child.id)
        var renamed = nested; renamed.title = "Soluzioni"; try await workspace.saveSection(renamed)
        let catalog = try await workspace.catalog()
        XCTAssertEqual(catalog.sections?.last?.pageIDs, [page.id])
        XCTAssertEqual(NotebookSections.pages(in: section.id, sections: catalog.sections ?? []), [page.id])
        let untouched = try await workspace.pageSnapshot(page.id); XCTAssertEqual(untouched, page)
        let ink = try await workspace.drawing(untouched); XCTAssertEqual(ink, Data([42, 15]))
        try await workspace.deletePage(page.id)
        try await workspace.restorePageOrder([page.id], expected: [])
        let reopened = try NativePackageInspector.inspect(workspace.package)
        XCTAssertEqual(reopened.manifest.pageIDs, [page.id])
        XCTAssertEqual(try CatalogRecovery.read("catalog.json", package: workspace.package).sections?.last?.pageIDs, [page.id])
        do { try await workspace.removeSection(child.id); XCTFail("Deleted populated section") } catch LibraryFailure.nonEmptyFolder { }
        try await workspace.assignPages([page.id], toSection: nil); try await workspace.removeSection(child.id)
        try await workspace.removeSection(section.id)
        let empty = try await workspace.catalog(); XCTAssertEqual(empty.sections, [])
    }

    func testCyclesMissingParentsDuplicateAssignmentsAndDeepTreesAreRejected() throws {
        let root = NotebookSection(title: "Radice"), page = UUID()
        var child = NotebookSection(title: "Figlia", parentID: root.id, pageIDs: [page])
        var cycle = root; cycle.parentID = child.id
        XCTAssertThrowsError(try NotebookSections.validate([cycle, child]))
        XCTAssertThrowsError(try NotebookSections.validate([child]))
        var repeated = root; repeated.pageIDs = [page]
        XCTAssertThrowsError(try NotebookSections.validate([repeated, child]))
        child.title = "\n"; XCTAssertThrowsError(try NotebookSections.validate([root, child]))
        var chain = [root]
        for i in 1...12 { chain.append(NotebookSection(title: "Livello \(i)", parentID: chain.last?.id)) }
        XCTAssertThrowsError(try NotebookSections.validate(chain))
        XCTAssertTrue(NotebookSections.outline(chain).isEmpty)
        XCTAssertNoThrow(try NotebookSections.validate(Array(chain.prefix(12))))
    }

    func testCloneAndMergeRemapSectionsAndPageIdentities() async throws {
        let (root, store, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage(), section = NotebookSection(title: "Lezioni")
        try await workspace.saveSection(section); try await workspace.assignPages([page.id], toSection: section.id)
        let copyID = UUID(), copyBook = UUID()
        try await workspace.clone(to: store, documentID: copyID, notebookID: copyBook)
        let copy = DocumentWorkspace(package: store.packageURL(for: copyID), documentID: copyID, notebookID: copyBook)
        let copiedPages = try await copy.pages(), copied = try await copy.catalog()
        XCTAssertNotEqual(copied.sections?.first?.id, section.id)
        XCTAssertEqual(copied.sections?.first?.pageIDs, copiedPages.map(\.id))
        let imported = try await workspace.appendNative(from: copy.package)
        let merged = try await workspace.catalog()
        XCTAssertEqual(merged.sections?.count, 2)
        XCTAssertEqual(merged.sections?.last?.pageIDs, imported.map(\.id))
        XCTAssertNotEqual(merged.sections?.last?.id, copied.sections?.first?.id)
        _ = try NativePackageInspector.inspect(workspace.package)
        XCTAssertEqual(merged.sections?.first?.pageIDs, [page.id])
    }

    func testInvalidMutationsLeaveCatalogAndPagesIntact() async throws {
        let (root, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage(), section = NotebookSection(title: "Indice")
        try await workspace.saveSection(section)
        do { try await workspace.assignPages([page.id], toSection: UUID()); XCTFail("Missing section accepted") } catch LibraryFailure.missingItem { }
        do { try await workspace.assignPages([UUID()], toSection: section.id); XCTFail("Missing page accepted") } catch LibraryFailure.missingItem { }
        var invalid = section; invalid.parentID = invalid.id
        do { try await workspace.saveSection(invalid); XCTFail("Cycle saved") } catch LibraryFailure.corruptDocument { }
        let stored = try await workspace.catalog(); XCTAssertEqual(stored.sections, [section])
        let pages = try await workspace.pages(); XCTAssertEqual(pages, [page])
        let legacy = DocumentCatalog(); let decoded = try JSONDecoder().decode(DocumentCatalog.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.sections)
    }
}
