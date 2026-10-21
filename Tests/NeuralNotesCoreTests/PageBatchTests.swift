import XCTest
@testable import NeuralNotesCore

final class PageBatchTests: XCTestCase {
    private func fixture() async throws -> (URL, NativeDocumentStore, DocumentWorkspace, [PageSnapshot]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), document = UUID(), book = UUID()
        let store = try NativeDocumentStore(root: root); try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        var first = PageSnapshot(); first.texts = [TextElement(text: "Da spostare")]
        first = try await workspace.addPage(first); let second = try await workspace.addPage()
        return (root, store, workspace, [first, second])
    }
    func testBatchTransfersContentsAndDrawingSnapshotsWithoutChangingOrder() async throws {
        let (root, _, workspace, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var next = original; next[1].texts = next[0].texts; next[0].texts = []
        let saved = try await workspace.applyPageBatch(next.map { PageMutation(page: $0, expectedRevision: $0.revision, drawing: Data([UInt8($0.id == next[0].id ? 1 : 2)])) })
        XCTAssertEqual(saved.map(\.revision), [1, 1])
        let pages = try await workspace.pages(); XCTAssertEqual(pages.map(\.id), original.map(\.id))
        XCTAssertTrue(pages[0].texts.isEmpty); XCTAssertEqual(pages[1].texts.first?.text, "Da spostare")
        let bytes = try await workspace.drawing(pages[1]); XCTAssertEqual(bytes, Data([2]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(PageBatchRecovery.path).path))
        _ = try NativePackageInspector.inspect(workspace.package)
    }
    func testStaleOrInvalidSecondPageCannotPartiallyChangeFirstPage() async throws {
        let (root, _, workspace, pages) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var changed = pages[0]; changed.texts = []
        do { try await workspace.applyPageBatch([PageMutation(page: changed, expectedRevision: 0, drawing: Data([1])), PageMutation(page: pages[1], expectedRevision: 99, drawing: Data([2]))]); XCTFail("Stale batch applied") } catch WorkspaceFailure.staleRevision { }
        var invalid = pages[1]; invalid.texts = [TextElement(text: "Non valido")]; invalid.texts[0].width = -5
        do { try await workspace.applyPageBatch([PageMutation(page: changed, expectedRevision: 0, drawing: Data([1])), PageMutation(page: invalid, expectedRevision: 0, drawing: Data([2]))]); XCTFail("Invalid geometry applied") } catch LibraryFailure.corruptDocument { }
        let unchanged = try await workspace.pages(); XCTAssertEqual(unchanged, pages)
        invalid = pages[1]; invalid.images = [ImageElement(file: "images/missing.png", width: 10, height: 10)]
        do { try await workspace.applyPageBatch([PageMutation(page: changed, expectedRevision: 0, drawing: Data()), PageMutation(page: invalid, expectedRevision: 0, drawing: Data())]); XCTFail("Missing media committed") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(PageBatchRecovery.path).path))
        let stillUnchanged = try await workspace.pages(); XCTAssertEqual(stillUnchanged, pages)
    }
    func testReopeningCompletesJournalAfterOnlyOnePageWasWritten() async throws {
        let (root, _, workspace, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before; after[1].texts = after[0].texts; after[0].texts = []
        for i in after.indices {
            after[i].revision += 1; after[i].drawingFile = "drawings/\(after[i].id)-\(UUID()).drawing"
            try Data([UInt8(i)]).write(to: workspace.package.appendingPathComponent(after[i].drawingFile!))
        }
        let journal = PageBatchJournal(documentID: workspace.documentID, notebookID: try await workspace.manifest().notebookID, entries: after.map { .init(expectedRevision: 0, page: $0) })
        try await workspace.write(journal, PageBatchRecovery.pathAfterCreatingDirectory(in: workspace.package))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(after[0]).write(to: workspace.package.appendingPathComponent("pages/\(after[0].id).json"), options: .atomic)
        _ = try NativeDocumentStore(root: root)
        let reopened = DocumentWorkspace(package: workspace.package, documentID: workspace.documentID, notebookID: journal.notebookID)
        let recovered = try await reopened.pages(); XCTAssertEqual(recovered, after)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
    func testBrokenRecoveryCannotOverwritePagesOrMakeOtherNotebooksDisappear() async throws {
        let (root, store, workspace, pages) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let path = try PageBatchRecovery.pathAfterCreatingDirectory(in: workspace.package)
        try Data("broken journal".utf8).write(to: workspace.package.appendingPathComponent(path))
        let other = UUID(), book = UUID(); try store.create(DocumentManifest(documentID: other, notebookID: book))
        let reopened = try NativeDocumentStore(root: root)
        XCTAssertNoThrow(try reopened.read(documentID: other, notebookID: book))
        XCTAssertThrowsError(try NativePackageInspector.inspect(workspace.package))
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(PageSnapshot.self, from: Data(contentsOf: workspace.package.appendingPathComponent("pages/\(pages[0].id).json"))), pages[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(path).path))
    }
    func testNormalSaveRejectsBadObjectGeometryBeforeReplacingReadablePage() async throws {
        let (root, _, workspace, pages) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var invalid = pages[0]; invalid.revision += 1; invalid.texts[0].fontSize = -1
        do { _ = try await workspace.save(invalid, drawing: Data([1])); XCTFail("Invalid text saved") } catch LibraryFailure.corruptDocument { }
        let current = try await workspace.pageSnapshot(pages[0].id); XCTAssertEqual(current, pages[0])
        invalid = pages[0]; invalid.revision = Int.max
        do { _ = try await workspace.save(invalid, drawing: Data()); XCTFail("Overflowing revision accepted") } catch LibraryFailure.corruptDocument { }
        for index in [-1, Int.max] {
            invalid = pages[0]; invalid.revision = 1; invalid.pdfIndex = index
            do { _ = try await workspace.save(invalid, drawing: Data()); XCTFail("Invalid PDF page index accepted") } catch LibraryFailure.corruptDocument { }
        }
        let retained = try await workspace.pageSnapshot(pages[0].id); XCTAssertEqual(retained, pages[0])
    }
}

private extension PageBatchRecovery {
    static func pathAfterCreatingDirectory(in package: URL) throws -> String {
        try FileManager.default.createDirectory(at: package.appendingPathComponent("recovery"), withIntermediateDirectories: true); return path
    }
}
