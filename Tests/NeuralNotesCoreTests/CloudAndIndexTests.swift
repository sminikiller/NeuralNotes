import XCTest
@testable import NeuralNotesCore

final class CloudAndIndexTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentWorkspace, Notebook) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), book = UUID(), doc = UUID()
        try store.create(DocumentManifest(documentID: doc, notebookID: book))
        let metadata = Notebook(id: book, documentID: doc, title: "Lezione", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        return (root, store, DocumentWorkspace(package: store.packageURL(for: doc), documentID: doc, notebookID: book), metadata)
    }
    func testThreeWayCloudPolicyNeverOverwritesIndependentEdits() {
        let checkpoint = CloudSyncCheckpoint(local: "old", remote: "old")
        XCTAssertEqual(CloudSyncPolicy.action(local: "new", remote: nil, checkpoint: nil), .upload)
        XCTAssertEqual(CloudSyncPolicy.action(local: "same", remote: "same", checkpoint: nil), .unchanged)
        XCTAssertEqual(CloudSyncPolicy.action(local: "local", remote: "remote", checkpoint: nil), .conflict)
        XCTAssertEqual(CloudSyncPolicy.action(local: "new", remote: "old", checkpoint: checkpoint), .upload)
        XCTAssertEqual(CloudSyncPolicy.action(local: "old", remote: "new", checkpoint: checkpoint), .download)
        XCTAssertEqual(CloudSyncPolicy.action(local: "a", remote: "b", checkpoint: checkpoint), .conflict)
    }
    func testAutomaticOCRIsRevisionBoundAndDoesNotModifyTheNotebook() async throws {
        let (root, _, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1; page = try await workspace.save(page, drawing: Data([1]))
        let stored = try await workspace.storeAutomaticOCR(pageID: page.id, revision: page.revision, text: "Teorema riconosciuto")
        XCTAssertTrue(stored)
        let chunks = try await workspace.indexedChunks(); XCTAssertTrue(chunks.contains { $0.text.contains("Teorema") })
        let header = try await workspace.pages().first; XCTAssertEqual(header?.lastEditedAt, page.lastEditedAt); XCTAssertEqual(header?.recognizedText, "")
        page.revision += 1; _ = try await workspace.save(page, drawing: Data([2]))
        let stale = try await workspace.storeAutomaticOCR(pageID: page.id, revision: 1, text: "Vecchio testo"); XCTAssertFalse(stale)
        let changed = try await workspace.indexedChunks(); XCTAssertTrue(changed.isEmpty)
    }
    func testCloudSnapshotReplacementRetainsBackupAndRejectsConcurrentLocalChange() async throws {
        let (root, _, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1; page.texts = [TextElement(text: "Originale")]
        page = try await workspace.save(page, drawing: Data([1]))
        let snapshot = try await workspace.cloudSnapshot(metadata: book)
        defer { try? FileManager.default.removeItem(at: snapshot.archive.deletingLastPathComponent()) }
        let incoming = root.appendingPathComponent("incoming.nnbook")
        try NativeArchive.extract(from: snapshot.archive, to: incoming)
        let remote = DocumentWorkspace(package: incoming, documentID: book.documentID, notebookID: book.id)
        var modified = page; modified.revision += 1; modified.texts[0].text = "Remoto"
        _ = try await remote.save(modified, drawing: Data([2]))
        page.revision += 1; page.texts[0].text = "Modifica locale"; _ = try await workspace.save(page, drawing: Data([3]))
        do { try await workspace.installCloudSnapshot(incoming, metadata: book, expectedLocal: snapshot.digest); XCTFail("Concurrent edit overwritten") }
        catch WorkspaceFailure.staleRevision { }
        let local = try await workspace.pages(); XCTAssertEqual(local.first?.texts.first?.text, "Modifica locale")
        let current = try SnapshotDigest.package(workspace.package, metadata: book)
        try await workspace.installCloudSnapshot(incoming, metadata: book, expectedLocal: current)
        let replaced = try await workspace.pages(); XCTAssertEqual(replaced.first?.texts.first?.text, "Remoto")
        let backups = try await workspace.automaticBackups(); XCTAssertEqual(backups.count, 1)
        let recovered = root.appendingPathComponent("restored.nnbook")
        try NativeArchive.extract(from: try XCTUnwrap(backups.first?.url), to: recovered)
        let previous = DocumentWorkspace(package: recovered, documentID: book.documentID, notebookID: book.id)
        let old = try await previous.pages(); XCTAssertEqual(old.first?.texts.first?.text, "Modifica locale")
    }
    func testStoreRecoversAnInterruptedCloudDirectoryReplacement() async throws {
        let (root, store, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        let previous = root.appendingPathComponent("\(book.documentID).cloudPrevious", isDirectory: true)
        try FileManager.default.moveItem(at: workspace.package, to: previous)
        _ = try NativeDocumentStore(root: root)
        XCTAssertNoThrow(try store.read(documentID: book.documentID, notebookID: book.id))
    }
    func testConversationCloningRemapsSourcesAndPreservesQuestions() async throws {
        let (root, store, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage()
        let answer = AIArtifact(text: "Risposta", references: [SourceReference(documentID: book.documentID, pageID: page.id)], provider: "Fixture")
        try await workspace.saveConversationTurn(AIConversationTurn(question: "Domanda", answer: answer))
        try await workspace.saveGlossaryEntry(GlossaryEntry(term: "Termine", definition: "Definizione", references: answer.references))
        let doc = UUID(), id = UUID(); try await workspace.clone(to: store, documentID: doc, notebookID: id)
        let copy = DocumentWorkspace(package: store.packageURL(for: doc), documentID: doc, notebookID: id)
        let pages = try await copy.pages(), catalog = try await copy.catalog()
        XCTAssertEqual(catalog.conversation?.first?.question, "Domanda")
        XCTAssertEqual(catalog.conversation?.first?.answer.references.first?.documentID, doc)
        XCTAssertEqual(catalog.conversation?.first?.answer.references.first?.pageID, pages.first?.id)
        XCTAssertEqual(catalog.glossary?.first?.references.first?.documentID, doc)
        XCTAssertEqual(catalog.glossary?.first?.references.first?.pageID, pages.first?.id)
        let appended = try await copy.appendNative(from: workspace.package)
        let merged = try await copy.catalog()
        XCTAssertEqual(merged.conversation?.count, 2)
        XCTAssertEqual(merged.conversation?.last?.question, "Domanda")
        XCTAssertEqual(merged.conversation?.last?.answer.references.first?.documentID, doc)
        XCTAssertEqual(merged.conversation?.last?.answer.references.first?.pageID, appended.first?.id)
        XCTAssertEqual(merged.glossary?.last?.references.first?.pageID, appended.first?.id)
    }
}
