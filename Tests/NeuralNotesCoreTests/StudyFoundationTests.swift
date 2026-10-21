import XCTest
@testable import NeuralNotesCore

final class StudyFoundationTests: XCTestCase {
    func testBackupBudgetRotationRemovesOldestButRetainsTwoRestorableCopies() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage()
        var saved: [URL] = []
        for i in 0..<4 {
            page.revision += 1; page.title = "Versione \(i)"
            page = try await workspace.save(page, drawing: Data([1]))
            let file = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0, maximumBytes: 1)
            saved.append(try XCTUnwrap(file))
        }
        let copies = try await workspace.automaticBackups()
        XCTAssertEqual(Set(copies.map(\.url)), Set(saved.suffix(2)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved[0].path))
        for (i, file) in saved.suffix(2).enumerated() {
            let output = root.appendingPathComponent("restored-\(i)")
            try NativeArchive.extract(from: file, to: output)
            let inspected = try NativePackageInspector.inspect(output)
            let restored = DocumentWorkspace(package: output, documentID: inspected.manifest.documentID, notebookID: inspected.manifest.notebookID)
            let pages = try await restored.pages(); XCTAssertEqual(pages.first?.title, "Versione \(i + 2)")
        }
    }
    func testBatchPageAppendValidatesBeforePublishingAndPreservesExistingInk() async throws {
        let (root, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var original = try await workspace.addPage(); original.revision = 1
        original = try await workspace.save(original, drawing: Data([9, 4]))
        let inputs = (0..<100).map { _ in PageSnapshot() }
        _ = try await workspace.appendPages(inputs)
        let pages = try await workspace.pages(); XCTAssertEqual(pages.count, 101); XCTAssertEqual(pages.first, original)
        let bytes = try await workspace.drawing(original); XCTAssertEqual(bytes, Data([9, 4]))
        let candidate = PageSnapshot()
        var invalid = PageSnapshot(); invalid.width = -1
        do { _ = try await workspace.appendPages([candidate, invalid]); XCTFail("Invalid batch accepted") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent("pages/\(candidate.id).json").path))
        let after = try await workspace.pages(); XCTAssertEqual(after, pages)
        do { _ = try await workspace.appendPages([inputs[0]]); XCTFail("Existing page overwritten") } catch { }
    }
    private func fixture() throws -> (URL, DocumentWorkspace, Notebook) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), id = UUID(), book = UUID()
        try store.create(DocumentManifest(documentID: id, notebookID: book))
        let metadata = Notebook(id: book, documentID: id, title: "Matematica", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        return (root, DocumentWorkspace(package: store.packageURL(for: id), documentID: id, notebookID: book), metadata)
    }
    func testIndexUpdatesAfterEditDeletionAndTranscriptCorrectionAndSurvivesReopen() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1; page.texts = [TextElement(text: "Prima versione")]
        page = try await workspace.save(page, drawing: Data([1]))
        let initial = try await workspace.indexedChunks(); XCTAssertEqual(initial.first?.text, "Prima versione")
        page.revision += 1; page.texts[0].text = "Versione corretta"; _ = try await workspace.save(page, drawing: Data([2]))
        let changed = try await workspace.indexedChunks(); XCTAssertEqual(changed.first?.text, "Versione corretta")
        var session = AudioSession(title: "Lezione"); session.transcript = [TranscriptSegment(start: 70, duration: 1, text: "Secondo minuto")]
        try await workspace.saveSession(session)
        let reopened = DocumentWorkspace(package: workspace.package, documentID: book.documentID, notebookID: book.id)
        let cached = try await reopened.indexedChunks()
        XCTAssertEqual(cached.count, 2); XCTAssertEqual(cached.last?.reference.seconds, 60)
        try await reopened.deletePage(page.id)
        let remaining = try await reopened.indexedChunks(); XCTAssertEqual(remaining.count, 1); XCTAssertNil(remaining.first?.reference.pageID)
    }
    func testAutomaticBackupRotatesOnlyCompleteArchivesAndSkipsActiveRecording() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        for _ in 0..<4 { _ = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0, keep: 2) }
        let copies = try await workspace.automaticBackups(); XCTAssertEqual(copies.count, 2)
        let output = root.appendingPathComponent("restored")
        try NativeArchive.extract(from: try XCTUnwrap(copies.first?.url), to: output)
        XCTAssertEqual(try NativePackageInspector.inspect(output).manifest.documentID, book.documentID)
        var session = AudioSession(title: "In corso"); session.state = "recording"; try await workspace.saveSession(session)
        let skipped = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0)
        XCTAssertNil(skipped)
        let unchanged = try await workspace.automaticBackups(); XCTAssertEqual(unchanged.count, 2)
    }
    func testAutomaticBackupIntervalAndInvalidMetadataCannotReplaceCopies() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        let first = try await workspace.createAutomaticBackup(metadata: book)
        XCTAssertNotNil(first)
        let second = try await workspace.createAutomaticBackup(metadata: book); XCTAssertNil(second)
        do { _ = try await workspace.createAutomaticBackup(metadata: book, keep: 0); XCTFail("Invalid retention accepted") }
        catch WorkspaceFailure.invalidPath { }
        let copies = try await workspace.automaticBackups(); XCTAssertEqual(copies.count, 1)
    }
    func testWritingSettingsRoundTripAndRejectInvalidPresets() throws {
        var options = WritingOptions(); options.pen = .fountainPen; options.markerOnly = true
        options.presets = [PenPreset(kind: .monoline, color: .blue, width: 2)]
        XCTAssertEqual(try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options)), options)
        options.presets[0].width = .nan; XCTAssertFalse(options.isValid)
        options = WritingOptions(); options.eraserWidth = 1000; XCTAssertFalse(options.isValid)
    }
}
