import XCTest
@testable import NeuralNotesCore

final class PageEditRecoveryTests: XCTestCase {
    private func fixture(count: Int = 3) async throws -> (URL, DocumentWorkspace, [PageSnapshot]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = UUID(), notebook = UUID(), store = try NativeDocumentStore(root: root)
        try store.create(DocumentManifest(documentID: document, notebookID: notebook))
        let writer = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: notebook)
        let pages = (0..<count).map { index -> PageSnapshot in var page = PageSnapshot(); page.texts = [TextElement(text: "Originale \(index)")]; return page }
        _ = try await writer.appendPages(pages)
        return (root, writer, pages)
    }
    private func prepare(_ writer: DocumentWorkspace, before: [PageSnapshot], after: [PageSnapshot], order: [UUID]? = nil) async throws -> PageEditJournal {
        let manifest = try await writer.manifest()
        let revisions = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.revision) })
        let journal = PageEditJournal(operationID: UUID(), documentID: writer.documentID, notebookID: manifest.notebookID,
            oldOrder: before.map(\.id), newOrder: order ?? after.map(\.id),
            entries: after.map { .init(pageID: $0.id, expectedRevision: revisions[$0.id]) })
        try FileManager.default.createDirectory(at: writer.package.appendingPathComponent(journal.directory), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        for page in after { try encoder.encode(page).write(to: writer.package.appendingPathComponent(journal.header(page.id)), options: .atomic) }
        try encoder.encode(journal).write(to: writer.package.appendingPathComponent(PageEditRecovery.path), options: .atomic)
        return journal
    }
    private func readPage(_ id: UUID, package: URL) throws -> PageSnapshot {
        try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: package.appendingPathComponent("pages/\(id).json")))
    }
    func testInterruptedHeadersFinishTogetherWithANewPageAndOrder() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before
        for i in after.indices { after[i].revision += 1; after[i].texts = [] }
        var new = PageSnapshot(); new.texts = before[0].texts; new.renewObjectIDs(); after.append(new)
        let order = [before[0].id, new.id] + before.dropFirst().map(\.id)
        let journal = try await prepare(writer, before: before, after: after, order: order)
        let first = try Data(contentsOf: writer.package.appendingPathComponent(journal.header(after[0].id)))
        try first.write(to: writer.package.appendingPathComponent("pages/\(after[0].id).json"), options: .atomic)
        let reopened = try NativeDocumentStore(root: root)
        let manifest = try reopened.read(documentID: writer.documentID, notebookID: journal.notebookID)
        XCTAssertEqual(manifest.pageIDs, order)
        for page in after { XCTAssertEqual(try readPage(page.id, package: writer.package), page) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.package.appendingPathComponent(PageEditRecovery.path).path))
        XCTAssertNoThrow(try NativePackageInspector.inspect(writer.package))
    }
    func testMissingAssetOnLastPageDoesNotTouchTheFirstHeader() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before
        for i in after.indices { after[i].revision += 1; after[i].texts = [] }
        after[after.count - 1].images = [ImageElement(file: "images/missing.png", width: 20, height: 30)]
        _ = try await prepare(writer, before: before, after: after)
        XCTAssertThrowsError(try PageEditRecovery.recover(in: writer.package))
        for page in before { XCTAssertEqual(try readPage(page.id, package: writer.package), page) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: writer.package.appendingPathComponent(PageEditRecovery.path).path))
    }
    func testAlreadyCommittedManifestIsSafeToReplayAndAStaleHeaderStopsBeforeWriting() async throws {
        let (root, writer, before) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var after = before
        for i in after.indices { after[i].revision += 1; after[i].texts = [] }
        let journal = try await prepare(writer, before: before, after: after, order: after.reversed().map(\.id))
        var stale = before[1]; stale.revision = 20
        try JSONEncoder().encode(stale).write(to: writer.package.appendingPathComponent("pages/\(stale.id).json"), options: .atomic)
        XCTAssertThrowsError(try PageEditRecovery.recover(in: writer.package))
        XCTAssertEqual(try readPage(before[0].id, package: writer.package), before[0])
        // A crash just before removing the pointer: all headers/order already match.
        for page in after {
            try Data(contentsOf: writer.package.appendingPathComponent(journal.header(page.id))).write(to: writer.package.appendingPathComponent("pages/\(page.id).json"), options: .atomic)
        }
        let manifestURL = writer.package.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(DocumentManifest.self, from: Data(contentsOf: manifestURL))
        manifest.pageIDs = journal.newOrder
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        try PageEditRecovery.recover(in: writer.package)
        for page in after { XCTAssertEqual(try readPage(page.id, package: writer.package), page) }
        XCTAssertNoThrow(try PageEditRecovery.recover(in: writer.package))
    }
    func testFifteenHundredHeadersAreRecoveredBeyondTheOldEightPageBatchLimit() async throws {
        let (root, writer, before) = try await fixture(count: 1500); defer { try? FileManager.default.removeItem(at: root) }
        var after = before
        for i in after.indices { after[i].revision += 1; after[i].texts = [] }
        _ = try await prepare(writer, before: before, after: after)
        try PageEditRecovery.recover(in: writer.package)
        for page in after { XCTAssertEqual(try readPage(page.id, package: writer.package), page) }
        XCTAssertNoThrow(try NativePackageInspector.inspect(writer.package))
    }
}
