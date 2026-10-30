import XCTest
@testable import NeuralNotesCore

final class PageEditSnapshotTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), document = UUID()
        let store = try NativeDocumentStore(root: root)
        try store.create(DocumentManifest(documentID: document, notebookID: UUID()))
        return (root, store.packageURL(for: document))
    }
    func testSnapshotOwnsImageAndDrawingAndRestoresMediaAfterNotebookCleanup() async throws {
        let (root, package) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let document = UUID(), bytes = Data([1, 2, 3, 4]), image = package.appendingPathComponent("images/photo.png")
        try bytes.write(to: image)
        var page = PageSnapshot(); page.images = [ImageElement(file: "images/photo.png", width: 100, height: 80)]
        let builder = try PageEditSnapshotBuilder(documentID: document, parent: root.appendingPathComponent("undo"))
        try await builder.append(page, drawing: Data([7, 8]), sourcePackage: package)
        let snapshot = try await builder.finish()
        XCTAssertEqual(snapshot.documentID, document); XCTAssertEqual(snapshot.pageIDs, [page.id])
        XCTAssertEqual(try snapshot.page(page.id), page)
        let savedInk = try XCTUnwrap(snapshot.drawingURL(page.id))
        XCTAssertEqual(try Data(contentsOf: savedInk), Data([7, 8]))
        try FileManager.default.removeItem(at: image)
        try snapshot.restoreMedia(in: package)
        XCTAssertEqual(try Data(contentsOf: image), bytes)
        try Data([9]).write(to: image)
        try snapshot.restoreMedia(in: package)
        XCTAssertEqual(try Data(contentsOf: image), Data([9]), "Il ripristino non sovrascrive file esistenti.")
        XCTAssertGreaterThan(snapshot.byteCount, 6)
    }
    func testDuplicatePageOrCorruptHeaderDoesNotReplaceTheReadableSnapshot() async throws {
        let (root, package) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let builder = try PageEditSnapshotBuilder(documentID: UUID(), parent: root.appendingPathComponent("undo"))
        var page = PageSnapshot(); page.texts = [TextElement(text: "Conservare")]
        try await builder.append(page, drawing: nil, sourcePackage: package)
        do { try await builder.append(page, drawing: Data([1]), sourcePackage: package); XCTFail("Duplicate accepted") } catch { }
        let snapshot = try await builder.finish()
        XCTAssertEqual(try snapshot.page(page.id), page); XCTAssertNil(try snapshot.drawingURL(page.id))
        do { _ = try await builder.finish(); XCTFail("Finished twice") } catch { }
        var invalid = page; invalid.id = UUID()
        try JSONEncoder().encode(invalid).write(to: snapshot.directory.appendingPathComponent("pages/\(page.id).json"), options: .atomic)
        XCTAssertThrowsError(try snapshot.page(page.id))
        XCTAssertThrowsError(try snapshot.page(UUID()))
    }
    func testDiskBudgetEvictsOlderEntriesButKeepsOneCompleteLargeUndoAndRedo() {
        var history = EditHistory<Int>(maximumCount: 10, maximumBytes: 100, maximumDiskBytes: 12)
        history.record(1, label: "Uno", cost: 1, diskCost: 8)
        history.record(2, label: "Due", cost: 1, diskCost: 8)
        XCTAssertEqual(history.undo?.event, 2); history.didUndo(); XCTAssertNil(history.undo)
        XCTAssertEqual(history.redo?.event, 2); history.didRedo()
        history.record(3, label: "Operazione grande", cost: 1, diskCost: 1000)
        XCTAssertEqual(history.undo?.event, 3); history.didUndo(); XCTAssertNil(history.undo)
        XCTAssertEqual(history.redo?.event, 3)
    }
    func testDiskBudgetDoesNotOverflowOrEraseTheNewestEvent() {
        var history = EditHistory<Int>(maximumDiskBytes: Int64.max)
        history.record(1, label: "Uno", diskCost: Int64.max)
        history.record(2, label: "Due", diskCost: Int64.max)
        XCTAssertEqual(history.undo?.event, 2); history.didUndo()
        XCTAssertNil(history.undo); XCTAssertEqual(history.redo?.event, 2)
    }
}
