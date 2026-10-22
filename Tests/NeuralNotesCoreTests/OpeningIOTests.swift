import XCTest
@testable import NeuralNotesCore

final class OpeningIOTests: XCTestCase {
    func testPageHeaderAndSelectedDrawingIOForSixTwelveAndThreeHundredPages() async throws {
        for count in [6, 12, 300] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try NativeDocumentStore(root: root)
            let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
            let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
            var inputs: [PageSnapshot] = []
            for i in 0..<count {
                var page = PageSnapshot(); page.title = "Pagina \(i + 1)"; page.lastEditedAt = Double(i)
                page.texts = (0..<20).map { TextElement(text: "Riga \($0): " + String(repeating: "appunti ", count: 20)) }
                page.images = (0..<4).map { ImageElement(file: "images/asset-\($0).png", width: 100, height: 100) }
                inputs.append(page)
            }
            _ = try await workspace.appendPages(inputs)
            let target = try XCTUnwrap(inputs.last)
            let drawn = try await workspace.save({ var value = target; value.revision = 1; return value }(), drawing: Data([10, 20, 30]))
            // A large audio file exists, but opening page metadata/drawing does not read it.
            let audio = try await workspace.url("audio/long-recording.caf")
            XCTAssertTrue(FileManager.default.createFile(atPath: audio.path, contents: nil))
            let file = try FileHandle(forWritingTo: audio); try file.truncate(atOffset: 300 * 1024 * 1024); try file.close()
            let start = ProcessInfo.processInfo.systemUptime
            let pages = try await workspace.pages()
            let headersMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
            XCTAssertEqual(pages.count, count); XCTAssertEqual(pages.last?.id, target.id)
            // An unrelated broken header must not prevent reading the destination.
            try Data("broken offscreen page".utf8).write(to: await workspace.url("pages/\(inputs[0].id).json"))
            let selectedStart = ProcessInfo.processInfo.systemUptime
            let current = try await workspace.pageSnapshot(target.id)
            let drawing = try await workspace.drawing(current)
            let selectedMS = (ProcessInfo.processInfo.systemUptime - selectedStart) * 1000
            XCTAssertEqual(current, drawn); XCTAssertEqual(drawing, Data([10, 20, 30]))
            print("OPEN_IO pages=\(count) headers_ms=\(String(format: "%.2f", headersMS)) selected_ms=\(String(format: "%.2f", selectedMS)) audio_bytes=314572800")
        }
    }

    func testCancelledAutomaticBackupKeepsProtectedCopiesAndRemovesPendingOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let book = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Backup interrotto", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        _ = try await workspace.addPage()
        for _ in 0..<2 { _ = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0) }
        let before = try await workspace.automaticBackups().map(\.url)
        try Data(repeating: 42, count: 16 * 1024 * 1024).write(to: await workspace.url("audio/large.caf"))
        let job = Task { try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0, maximumBytes: 1) }
        try await Task.sleep(for: .milliseconds(10)); job.cancel()
        do { _ = try await job.value; XCTFail("Cancelled backup completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        let after = try await workspace.automaticBackups().map(\.url)
        XCTAssertEqual(after, before)
        let files = try FileManager.default.contentsOfDirectory(atPath: workspace.automaticBackupDirectory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("pending-") })
        for url in before { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }
}
