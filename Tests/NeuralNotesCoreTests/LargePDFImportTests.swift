import XCTest
@testable import NeuralNotesCore

final class LargePDFImportTests: XCTestCase {
    private func payload(_ url: URL, bytes: UInt64) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        try file.write(contentsOf: Data("%PDF-1.7\n".utf8)); try file.truncate(atOffset: bytes)
    }
    private func fixture() throws -> (URL, DocumentWorkspace, DocumentManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NN-PDF-test-\(UUID())")
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        return (root, DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID), manifest)
    }
    func testSevenHundredMiBTransportAndFifteenHundredPagePublicationAreBoundedAndPreserveSource() async throws {
        let (root, workspace, manifest) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("large-source.pdf"), temp = root.appendingPathComponent("staged.pdf")
        // Synthetic sparse bytes test transport/storage, not PDF parsing. The
        // separate Apple test builds an actual 1500-page PDF and reads its text.
        try payload(source, bytes: 700 << 20)
        let staged = try PDFFileImport.stage(from: source, to: temp)
        XCTAssertEqual(staged.bytes, 700 << 20)
        // Independent Python hashlib digest of the header plus zero padding.
        XCTAssertEqual(staged.sha256, "100e654ea3898190d3e26ca5c81f0dbcbf0273f3f4db926b91a48b7d79f313e1")
        var original = PageSnapshot(); original.texts = [TextElement(text: "Appunti precedenti")]
        _ = try await workspace.addPage(original)
        let pages = (0..<1500).map { index -> PageSnapshot in var page = PageSnapshot(); page.pdfIndex = index; return page }
        let installed = try await workspace.installPDF(staged, name: "large-source.pdf", pages: pages)
        XCTAssertEqual(installed.count, 1500); XCTAssertEqual(Set(installed.compactMap(\.pdfFile)).count, 1)
        XCTAssertTrue(installed.allSatisfy { $0.texts.isEmpty && $0.drawingFile == nil })
        let catalog = try await workspace.catalog(), current = try await workspace.manifest()
        XCTAssertEqual(catalog.attachments.count, 1); XCTAssertEqual(current.pageIDs.count, 1501)
        let last = try await workspace.pageSnapshot(installed.last!.id); XCTAssertEqual(last.pdfIndex, 1499)
        let old = try await workspace.pageSnapshot(original.id); XCTAssertEqual(old.texts, original.texts)
        let file = try await workspace.url(catalog.attachments[0].file)
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, 700 << 20)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertEqual(try NativePackageInspector.inspect(workspace.package).manifest.documentID, manifest.documentID)
    }
    func testSpaceSizeAndExistingDestinationAreRejectedBeforeWriting() throws {
        let (root, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf"), temp = root.appendingPathComponent("staged.pdf")
        try payload(source, bytes: 1024)
        XCTAssertThrowsError(try PDFFileImport.stage(from: source, to: temp, availableBytes: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        try Data("keep".utf8).write(to: temp)
        XCTAssertThrowsError(try PDFFileImport.stage(from: source, to: temp))
        XCTAssertEqual(try Data(contentsOf: temp), Data("keep".utf8))
        let huge = root.appendingPathComponent("too-big.pdf")
        try payload(huge, bytes: UInt64(PDFImportPolicy.maximumBytes) + 1)
        XCTAssertThrowsError(try PDFFileImport.stage(from: huge, to: root.appendingPathComponent("not-created.pdf")))
    }
    func testCancellationRemovesOnlyThePrivateStagingFile() async throws {
        let (root, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf"), temp = root.appendingPathComponent("staged.pdf")
        try payload(source, bytes: 8 << 20)
        let job = Task.detached {
            try PDFFileImport.stage(from: source, to: temp) { copied, _ in
                if copied > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await job.value; XCTFail("Copy must cancel") } catch is CancellationError { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertEqual(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, 8 << 20)
    }
    func testDuplicatePageCannotOverwriteExistingOrTrashedHeaders() async throws {
        let (root, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try await workspace.addDefaultPage()
        let file = try await workspace.url("pages/\(original.id).json"), before = try Data(contentsOf: file)
        let source = root.appendingPathComponent("source.pdf"), temp = root.appendingPathComponent("staged.pdf")
        try payload(source, bytes: 1024)
        let staged = try PDFFileImport.stage(from: source, to: temp)
        var duplicate = original; duplicate.pdfIndex = 0
        do { _ = try await workspace.installPDF(staged, name: "source.pdf", pages: [duplicate]); XCTFail("Duplicate id") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))
        let catalog = try await workspace.catalog(); XCTAssertTrue(catalog.attachments.isEmpty)
    }
    func testNativeBackupRoundTripRetainsSharedPDFAndAllFifteenHundredPages() async throws {
        let (root, workspace, manifest) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf"), temp = root.appendingPathComponent("staged.pdf")
        try payload(source, bytes: 16384)
        let staged = try PDFFileImport.stage(from: source, to: temp)
        let pages = (0..<1500).map { index -> PageSnapshot in var page = PageSnapshot(); page.pdfIndex = index; return page }
        _ = try await workspace.installPDF(staged, name: "source.pdf", pages: pages)
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "PDF", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let archive = root.appendingPathComponent("roundtrip.nnbackup"), extracted = root.appendingPathComponent("extracted.nnbook")
        try NativeArchive.write(package: workspace.package, metadata: metadata, to: archive)
        try NativeArchive.extract(from: archive, to: extracted)
        let inspected = try NativePackageInspector.inspect(extracted); XCTAssertEqual(inspected.manifest.pageIDs.count, 1500)
        let copies = try FileManager.default.contentsOfDirectory(at: extracted.appendingPathComponent("attachments"), includingPropertiesForKeys: nil)
        XCTAssertEqual(copies.count, 1)
    }
}
