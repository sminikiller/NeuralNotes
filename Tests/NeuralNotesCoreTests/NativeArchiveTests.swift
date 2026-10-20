import XCTest
@testable import NeuralNotesCore

final class NativeArchiveTests: XCTestCase {
    func testStreamingMediaAndTwoHundredPageHeadersSurviveBackup() async throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        for index in 0..<200 {
            var page = try await workspace.addPage(); page.revision = 1; page.title = "Pagina \(index)"
            _ = try await workspace.save(page, drawing: Data([UInt8(truncatingIfNeeded: index)]))
        }
        let file = try await workspace.url("audio/stream.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        let chunk = Data((0..<65536).map { UInt8(truncatingIfNeeded: $0) })
        for _ in 0..<128 { try handle.write(contentsOf: chunk) }; try handle.close()
        var session = AudioSession(title: "Synthetic media IO fixture")
        var segment = AudioTimelineSegment(file: "audio/stream.bin", start: 0, hostStart: 0); segment.duration = 60
        session.segments = [segment]; session.state = "finished"; try await workspace.saveSession(session)
        let archive = root.appendingPathComponent("Large.nnbackup"); try NativeArchive.write(package: workspace.package, metadata: metadata, to: archive)
        let output = root.appendingPathComponent("Extracted.nnbook"); try NativeArchive.extract(from: archive, to: output)
        let copied = output.appendingPathComponent("audio/stream.bin")
        XCTAssertEqual(try copied.resourceValues(forKeys: [.fileSizeKey]).fileSize, 8 * 1024 * 1024)
        let input = try FileHandle(forReadingFrom: copied); defer { try? input.close() }
        for _ in 0..<128 { XCTAssertEqual(try input.read(upToCount: chunk.count), chunk) }
        XCTAssertEqual(try NativePackageInspector.inspect(output).manifest.pageIDs.count, 200)
    }
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentManifest, Notebook) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root.appendingPathComponent("Library"))
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Fisica",
            createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        return (root, store, manifest, metadata)
    }

    func testBackupPreservesBinaryMediaAndImportsIndependentIdentities() async throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
            documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision = 1
        page.title = "Forze"; page.isBookmarked = true
        let bytes = Data((0..<700_000).map { UInt8(truncatingIfNeeded: $0) })
        page = try await workspace.save(page, drawing: bytes)
        let artifact = AIArtifact(text: "Fonte", references: [SourceReference(documentID: manifest.documentID, pageID: page.id)], provider: "Test")
        try await workspace.saveArtifact(artifact)
        let archive = root.appendingPathComponent("Test.nnbackup")
        try NativeArchive.write(package: workspace.package, metadata: metadata, to: archive)
        let newDocument = UUID(), newNotebook = UUID()
        let imported = try NativeImport.copy(from: archive, into: store, documentID: newDocument, notebookID: newNotebook)
        XCTAssertEqual(imported?.title, "Fisica")
        let copy = DocumentWorkspace(package: store.packageURL(for: newDocument), documentID: newDocument, notebookID: newNotebook)
        let pages = try await copy.pages(), artifacts = try await copy.artifacts()
        XCTAssertEqual(pages.first?.title, "Forze"); XCTAssertEqual(pages.first?.isBookmarked, true)
        XCTAssertNotEqual(pages.first?.id, page.id)
        let data = try await copy.drawing(pages[0])
        XCTAssertEqual(data, bytes)
        XCTAssertEqual(artifacts.first?.references.first?.documentID, newDocument)
        XCTAssertEqual(artifacts.first?.references.first?.pageID, pages[0].id)
        XCTAssertNotEqual(artifacts.first?.id, artifact.id)
        XCTAssertEqual(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID).pageIDs, [page.id])
    }

    func testCorruptedPayloadIsRejectedAndNoPartialPackageRemains() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Test.nnbackup")
        try NativeArchive.write(package: store.packageURL(for: manifest.documentID), metadata: metadata, to: archive)
        var data = try Data(contentsOf: archive); data[data.count - 1] ^= 1
        try data.write(to: archive)
        let output = root.appendingPathComponent("Corrupt.nnbook")
        XCTAssertThrowsError(try NativeArchive.extract(from: archive, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertNoThrow(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID))
    }

    func testMergingOwnBackupPreservesExistingPagesAndRemapsCardSources() async throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([42, 18]))
        let card = StudyCard(question: "Forza?", answer: "Massa per accelerazione", source: SourceReference(documentID: manifest.documentID, pageID: page.id))
        try await workspace.addStudyCards([card])
        let archive = root.appendingPathComponent("Merge.nnbackup")
        try NativeArchive.write(package: workspace.package, metadata: metadata, to: archive)
        let added = try await workspace.appendNative(from: archive)
        let pages = try await workspace.pages(), cards = try await workspace.catalog().studyCards ?? []
        XCTAssertEqual(pages.count, 2); XCTAssertEqual(pages[0].id, page.id)
        XCTAssertEqual(added.count, 1); XCTAssertNotEqual(added[0].id, page.id)
        XCTAssertNotEqual(added[0].drawingFile, page.drawingFile)
        let originalBytes = try await workspace.drawing(page), copiedBytes = try await workspace.drawing(added[0])
        XCTAssertEqual(originalBytes, copiedBytes)
        XCTAssertEqual(cards.count, 2); XCTAssertNotEqual(cards[0].id, cards[1].id)
        XCTAssertEqual(cards[1].source.documentID, manifest.documentID)
        XCTAssertEqual(cards[1].source.pageID, added[0].id)
    }

    func testMalformedMergeLeavesOriginalManifestAndDrawingUntouched() async throws {
        let (root, store, manifest, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([42]))
        let bad = root.appendingPathComponent("Bad.nnbackup"); try Data([1, 2, 3]).write(to: bad)
        do { _ = try await workspace.appendNative(from: bad); XCTFail("Invalid backup accepted") }
        catch { }
        let pages = try await workspace.pages(), bytes = try await workspace.drawing(page)
        XCTAssertEqual(pages.map(\.id), [page.id]); XCTAssertEqual(bytes, Data([42]))
    }

    func testTruncatedBackupDoesNotRegisterANotebook() throws {
        let (root, store, manifest, metadata) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Test.nnbackup")
        try NativeArchive.write(package: store.packageURL(for: manifest.documentID), metadata: metadata, to: archive)
        let full = try Data(contentsOf: archive)
        for length in [0, 7, 15, full.count - 1] {
            try full.prefix(length).write(to: archive)
            let id = UUID()
            XCTAssertThrowsError(try NativeImport.copy(from: archive, into: store, documentID: id, notebookID: UUID()))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.packageURL(for: id).path))
        }
    }

    func testLegacyPageAndCatalogRemainDecodable() throws {
        let id = UUID()
        let page = Data("{\"id\":\"\(id)\",\"revision\":0,\"width\":768,\"height\":1024,\"paper\":\"plain\",\"texts\":[],\"images\":[],\"anchors\":[],\"recognizedText\":\"\"}".utf8)
        let decoded = try JSONDecoder().decode(PageSnapshot.self, from: page)
        XCTAssertNil(decoded.title); XCTAssertNil(decoded.isBookmarked)
        let catalog = try JSONDecoder().decode(DocumentCatalog.self, from: Data("{\"schemaVersion\":1,\"attachments\":[],\"sessions\":[]}".utf8))
        XCTAssertNil(catalog.coverImageFile)
        XCTAssertNil(catalog.studyCards)
    }

    func testArchiveRejectsTraversalAndCaseFoldedCollisionsBeforeExtraction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for paths in [["images/../../escape"], ["images/a.png", "images/A.png"]] {
            let entries = paths.map { ["path": $0, "size": 0, "checksum": 0] as [String: Any] }
            let header = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": entries])
            var bytes = Data("NNBOOK01".utf8)
            let length = UInt64(header.count)
            bytes.append(contentsOf: (0..<8).map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) })
            bytes.append(header)
            let archive = root.appendingPathComponent("Bad.nnbackup"), output = root.appendingPathComponent("Output.nnbook")
            try bytes.write(to: archive)
            XCTAssertThrowsError(try NativeArchive.extract(from: archive, to: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }
}
