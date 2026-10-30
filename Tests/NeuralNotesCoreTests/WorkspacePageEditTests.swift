import XCTest
@testable import NeuralNotesCore

final class WorkspacePageEditTests: XCTestCase {
    private func fixture() async throws -> (URL, DocumentWorkspace, [PageSnapshot]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = UUID(), notebook = UUID(), store = try NativeDocumentStore(root: root)
        try store.create(DocumentManifest(documentID: document, notebookID: notebook))
        let writer = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: notebook)
        var first = PageSnapshot(); first.texts = [TextElement(text: "Appunti conservati")]
        let pages = [first, PageSnapshot()]; _ = try await writer.appendPages(pages)
        return (root, writer, pages)
    }
    private func snapshot(_ pages: [PageSnapshot], writer: DocumentWorkspace, root: URL, ink: Data? = nil) async throws -> PageEditSnapshot {
        let builder = try PageEditSnapshotBuilder(documentID: writer.documentID, parent: root.appendingPathComponent("history"))
        for page in pages { try await builder.append(page, drawing: ink, sourcePackage: writer.package) }
        return try await builder.finish()
    }
    func testMoveToNewPageAndSingleUndoRedoKeepBothContentsAndActiveOrder() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let oldOrder = before.map(\.id)
        let old = try await snapshot([before[0]], writer: writer, root: root, ink: Data([1, 2]))
        var source = before[0]; source.texts = []
        var destination = PageSnapshot(); destination.texts = before[0].texts; destination.renewObjectIDs()
        let after = try await snapshot([source, destination], writer: writer, root: root, ink: Data([3, 4]))
        let order = [source.id, destination.id, before[1].id]
        try await writer.applyPageEdit(after, expectedOrder: oldOrder, newOrder: order, expectedRevisions: [source.id: 0])
        let moved = try await writer.pages()
        XCTAssertEqual(moved.map(\.id), order); XCTAssertTrue(moved[0].texts.isEmpty)
        XCTAssertEqual(moved[1].texts.first?.text, before[0].texts.first?.text)
        XCTAssertNotEqual(moved[1].texts.first?.id, before[0].texts.first?.id)
        try await writer.applyPageEdit(old, expectedOrder: order, newOrder: oldOrder, expectedRevisions: [source.id: 1])
        let undone = try await writer.pages(), originalInk = try await writer.drawing(undone[0])
        XCTAssertEqual(undone.map(\.id), oldOrder); XCTAssertEqual(undone[0].texts, before[0].texts)
        XCTAssertEqual(originalInk, Data([1, 2]))
        let retained = try await writer.retainedPageSnapshot(destination.id)
        XCTAssertEqual(retained?.id, destination.id)
        try await writer.applyPageEdit(after, expectedOrder: oldOrder, newOrder: order,
            expectedRevisions: [source.id: undone[0].revision, destination.id: try XCTUnwrap(retained).revision])
        let redone = try await writer.pages(), copiedInk = try await writer.drawing(redone[1])
        XCTAssertEqual(redone.map(\.id), order); XCTAssertEqual(redone[1].texts, destination.texts)
        XCTAssertEqual(copiedInk, Data([3, 4]))
        XCTAssertNoThrow(try NativePackageInspector.inspect(writer.package))
    }
    func testStaleLastPageOrOrderCannotPartiallyApplyTheFirstPage() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before; after[0].texts = []; after[1].texts = [TextElement(text: "Copia")]
        let states = try await snapshot(after, writer: writer, root: root)
        do {
            try await writer.applyPageEdit(states, expectedOrder: before.map(\.id), newOrder: before.map(\.id),
                expectedRevisions: [before[0].id: 0, before[1].id: 99])
            XCTFail("Stale transaction applied")
        } catch WorkspaceFailure.staleRevision { }
        let unchanged = try await writer.pages(); XCTAssertEqual(unchanged, before)
        do {
            try await writer.applyPageEdit(states, expectedOrder: before.reversed().map(\.id), newOrder: before.map(\.id),
                expectedRevisions: [before[0].id: 0, before[1].id: 0])
            XCTFail("Wrong order applied")
        } catch WorkspaceFailure.staleRevision { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.package.appendingPathComponent(PageEditRecovery.path).path))
    }
    func testMissingLastMediaDoesNotPublishAnyPreparedHeader() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before; after[0].texts = []
        let states = try await snapshot(after, writer: writer, root: root)
        after[1].images = [ImageElement(file: "images/missing.png", width: 10, height: 10)]
        try JSONEncoder().encode(after[1]).write(to: states.directory.appendingPathComponent("pages/\(after[1].id).json"), options: .atomic)
        do {
            try await writer.applyPageEdit(states, expectedOrder: before.map(\.id), newOrder: before.map(\.id),
                expectedRevisions: [before[0].id: 0, before[1].id: 0])
            XCTFail("Missing media applied")
        } catch { }
        let unchanged = try await writer.pages(); XCTAssertEqual(unchanged, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.package.appendingPathComponent(PageEditRecovery.path).path))
    }
    func testCancelledPreparationLeavesTheNotebookUnchanged() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before; after[0].texts = []
        let states = try await snapshot(after, writer: writer, root: root)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await writer.applyPageEdit(states, expectedOrder: before.map(\.id), newOrder: before.map(\.id),
                expectedRevisions: [before[0].id: 0, before[1].id: 0])
        }
        do { try await task.value; XCTFail("Cancelled preparation committed") } catch is CancellationError { }
        let unchanged = try await writer.pages(); XCTAssertEqual(unchanged, before)
    }
}
