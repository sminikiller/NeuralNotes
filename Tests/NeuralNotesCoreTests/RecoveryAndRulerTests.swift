import XCTest
@testable import NeuralNotesCore

final class RecoveryAndRulerTests: XCTestCase {
    private func fixture() throws -> (URL, DocumentWorkspace, Notebook) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let book = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Prova", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        return (root, DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID), book)
    }
    func testBackupOrderSurvivesRoundedOrRewrittenModificationTimes() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage(); var written: [URL] = []
        for _ in 0..<5 {
            let url = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0, maximumBytes: 1)
            written.append(try XCTUnwrap(url))
            for entry in try await workspace.automaticBackups() {
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: entry.url.path)
            }
        }
        let copies = try await workspace.automaticBackups()
        XCTAssertEqual(copies.map { $0.url.path }, Array(written.suffix(2).reversed()).map(\.path))
        for item in written.suffix(2) {
            let destination = root.appendingPathComponent(UUID().uuidString)
            try NativeArchive.extract(from: item, to: destination)
            XCTAssertEqual(try NativePackageInspector.inspect(destination).manifest.documentID, book.documentID)
        }
    }
    func testBackupReturnedURLAndListedURLUseTheSameCanonicalPathThroughAnAlias() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real"), alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let store = try NativeDocumentStore(root: alias), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        _ = try await workspace.addPage()
        let book = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Alias", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let written = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0)
        let listed = try await workspace.automaticBackups()
        XCTAssertEqual(written?.path, listed.first?.url.path)
    }
    func testBulkPageTrashAndRestoreAreAtomicAndKeepMedia() async throws {
        let (root, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var pages = try await workspace.appendPages((0..<4).map { _ in PageSnapshot() })
        pages[1].revision = 1; pages[1] = try await workspace.save(pages[1], drawing: Data([6, 4]))
        do { try await workspace.deletePages([pages[0].id, UUID()]); XCTFail("Partial deletion") } catch { }
        var active = try await workspace.pages(); XCTAssertEqual(active.count, 4)
        try await workspace.deletePages([pages[1].id, pages[3].id])
        active = try await workspace.pages(); XCTAssertEqual(active.map(\.id), [pages[0].id, pages[2].id])
        let trash = try await workspace.storageReport().removedPages
        XCTAssertEqual(Set(trash.map(\.id)), [pages[1].id, pages[3].id])
        do { try await workspace.restoreRemovedPages([pages[1].id, UUID()]); XCTFail("Partial restore") } catch { }
        try await workspace.restoreRemovedPages([pages[3].id, pages[1].id])
        active = try await workspace.pages(); XCTAssertEqual(active.map(\.id), [pages[0].id, pages[2].id, pages[3].id, pages[1].id])
        let bytes = try await workspace.drawing(pages[1]); XCTAssertEqual(bytes, Data([6, 4]))
    }
    func testRulerProjectsFarAwayPointsOntoOneEdgeAndClipsToThePage() throws {
        for angle in [0.0, .pi / 6, .pi / 4, .pi / 2, -.pi * 0.75] {
            let guide = RulerGuide(x: 384, y: 512, angle: angle)
            let edge = guide.edge(nearest: StrokeSample(x: 300, y: 900))
            for p in [StrokeSample(x: -200, y: -500), StrokeSample(x: 2000, y: 1700), StrokeSample(x: 350, y: 900)] {
                let q = try XCTUnwrap(guide.project(p, edge: edge, width: 768, height: 1024))
                let distance = (q.x - guide.x) * -sin(angle) + (q.y - guide.y) * cos(angle)
                XCTAssertEqual(distance, edge * RulerGuide.halfWidth, accuracy: 1e-8)
                XCTAssertGreaterThanOrEqual(q.x, -1e-8); XCTAssertLessThanOrEqual(q.x, 768 + 1e-8)
                XCTAssertGreaterThanOrEqual(q.y, -1e-8); XCTAssertLessThanOrEqual(q.y, 1024 + 1e-8)
            }
        }
        var guide = RulerGuide(angle: .pi / 4 + 0.05); guide.snapAngle(); XCTAssertEqual(guide.angle, .pi / 4, accuracy: 1e-8)
        XCTAssertNil(RulerGuide(x: .nan).project(StrokeSample(x: 1, y: 1), edge: 1, width: 768, height: 1024))
    }
    func testFiveFocusToolsPersistAndSixAreRejected() throws {
        var profile = EditorWorkspace(name: "Focus", favorites: [.pen, .marker, .eraser])
        profile.focusTools = [.pen, .marker, .eraser, .lasso, .objects]; XCTAssertTrue(profile.isValid)
        let copy = try JSONDecoder().decode(EditorWorkspace.self, from: JSONEncoder().encode(profile)); XCTAssertEqual(copy.effectiveFocusTools.count, 5)
        profile.focusTools?.append(.ruler); XCTAssertFalse(profile.isValid)
    }
    func testBackupCloneKeepsTrashedPagesAndRemapsTheirAudioAnchors() async throws {
        let (root, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let live = try await workspace.addPage()
        var removed = try await workspace.addPage(); removed.revision = 1; removed.title = "Da ripristinare"
        var session = AudioSession(title: "Voce"); session.state = "finished"
        removed.anchors = [StrokeAnchor(signature: "stroke", audioSessionID: session.id, seconds: 0)]
        try await workspace.saveSession(session)
        removed = try await workspace.save(removed, drawing: Data([8, 9]))
        try await workspace.deletePage(removed.id)
        let archive = try await workspace.exportNative(metadata: book); defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let store = try NativeDocumentStore(root: root.appendingPathComponent("copies")), document = UUID(), notebook = UUID()
        _ = try NativeImport.copy(from: archive, into: store, documentID: document, notebookID: notebook)
        let copy = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: notebook)
        let active = try await copy.pages(); XCTAssertEqual(active.count, 1); XCTAssertNotEqual(active.first?.id, live.id)
        let trash = try await copy.storageReport().removedPages; XCTAssertEqual(trash.count, 1)
        let page = try XCTUnwrap(trash.first), catalog = try await copy.catalog()
        XCTAssertNotEqual(page.id, removed.id); XCTAssertEqual(page.anchors.first?.audioSessionID, catalog.sessions.first?.id)
        try await copy.restoreRemovedPage(page.id)
        let data = try await copy.drawing(page); XCTAssertEqual(data, Data([8, 9]))
    }
    func testRecoveryFolderScanSkipsSymlinksAndDoesNotModifySources() throws {
        let (root, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try Data(contentsOf: workspace.package.appendingPathComponent("manifest.json"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("duplicate"), withDestinationURL: workspace.package)
        let found = try NativeRecoveryScan.packages(in: root)
        XCTAssertEqual(found.count, 1); XCTAssertEqual(found.first?.lastPathComponent, workspace.package.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: workspace.package.appendingPathComponent("manifest.json")), before)
    }
    func testLegacyNNBOOK01FixtureImportsWithNewIdentitiesAndFormatErrorsKeepSource() throws {
        // Fixed v1 container with the original page fields, CRCs generated
        // independently with zlib, not by the current NativeArchive writer.
        let fixture = "Tk5CT09LMDHoAAAAAAAAAHsidmVyc2lvbiI6MSwiZW50cmllcyI6W3sicGF0aCI6Im1hbmlmZXN0Lmpzb24iLCJzaXplIjoyMDksImNoZWNrc3VtIjoyMDYwMDMyMzAwfSx7InBhdGgiOiJwYWdlcy8zMzMzMzMzMy0zMzMzLTMzMzMtMzMzMy0zMzMzMzMzMzMzMzMuanNvbiIsInNpemUiOjE3NCwiY2hlY2tzdW0iOjIxMjU3ODAwMTV9LHsicGF0aCI6Im1ldGFkYXRhLmpzb24iLCJzaXplIjoyMzMsImNoZWNrc3VtIjo4MjI4MTU4NzV9XX17InNjaGVtYVZlcnNpb24iOjEsImRvY3VtZW50SUQiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJub3RlYm9va0lEIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIiwicGFnZUlEcyI6WyIzMzMzMzMzMy0zMzMzLTMzMzMtMzMzMy0zMzMzMzMzMzMzMzMiXSwiY3JlYXRlZEF0IjoiMjAyNi0xMC0xOVQxMjowMDowMFoifXsiaWQiOiIzMzMzMzMzMy0zMzMzLTMzMzMtMzMzMy0zMzMzMzMzMzMzMzMiLCJyZXZpc2lvbiI6MCwid2lkdGgiOjc2OCwiaGVpZ2h0IjoxMDI0LCJwYXBlciI6InBsYWluIiwidGV4dHMiOltdLCJpbWFnZXMiOltdLCJhbmNob3JzIjpbXSwicmVjb2duaXplZFRleHQiOiJBcHB1bnRvIHByZWNlZGVudGUifXsiaWQiOiIyMjIyMjIyMi0yMjIyLTIyMjItMjIyMi0yMjIyMjIyMjIyMjIiLCJkb2N1bWVudElEIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwidGl0bGUiOiJRdWFkZXJubyBwcmVjZWRlbnRlIiwiY3JlYXRlZEF0IjoiMjAyNi0xMC0xOVQxMjowMDowMFoiLCJ1cGRhdGVkQXQiOiIyMDI2LTEwLTE5VDEyOjAwOjAwWiIsImNvdmVyIjoibGFnb29uIiwiaXNGYXZvcml0ZSI6ZmFsc2V9"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("precedente.nnbackup"), data = try XCTUnwrap(Data(base64Encoded: fixture))
        try data.write(to: archive)
        let store = try NativeDocumentStore(root: root.appendingPathComponent("Notebooks")), document = UUID(), book = UUID()
        let metadata = try NativeImport.copy(from: archive, into: store, documentID: document, notebookID: book)
        XCTAssertEqual(metadata?.title, "Quaderno precedente")
        XCTAssertEqual(try store.read(documentID: document, notebookID: book).pageIDs.count, 1)
        XCTAssertEqual(try Data(contentsOf: archive), data)
        let zip = root.appendingPathComponent("wrong.nnbackup"), bytes = Data([0x50, 0x4b, 3, 4, 0, 0, 0, 0])
        try bytes.write(to: zip)
        do { try NativeArchive.extract(from: zip, to: root.appendingPathComponent("output")); XCTFail("ZIP accepted as NNBOOK01") }
        catch NativeArchiveFailure.unrecognizedFormat(let kind) { XCTAssertTrue(kind.contains("ZIP")) }
        XCTAssertEqual(try Data(contentsOf: zip), bytes)
    }

}
