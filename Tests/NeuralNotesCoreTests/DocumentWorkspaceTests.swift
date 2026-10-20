import Foundation
import XCTest
@testable import NeuralNotesCore

final class DocumentWorkspaceTests: XCTestCase {
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentManifest, DocumentWorkspace) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        return (root, store, manifest, DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
            documentID: manifest.documentID, notebookID: manifest.notebookID))
    }

    func testPageRevisionsSurviveRestartAndKeepPreviousSnapshot() async throws {
        let (root, store, manifest, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage()
        page.revision = 1; page.paper = .grid; page.texts = [TextElement(text: "Appunti salvati")]
        page = try await workspace.save(page, drawing: Data([1, 2, 3]))
        let firstFile = page.drawingFile
        page.revision = 2
        page = try await workspace.save(page, drawing: Data([4, 5, 6]))
        XCTAssertEqual(page.previousDrawingFile, firstFile)
        let reopened = DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
            documentID: manifest.documentID, notebookID: manifest.notebookID)
        let pages = try await reopened.pages()
        XCTAssertEqual(pages.count, 1); XCTAssertEqual(pages[0].revision, 2)
        XCTAssertEqual(pages[0].paper, .grid); XCTAssertEqual(pages[0].texts[0].text, "Appunti salvati")
        let bytes = try await reopened.drawing(pages[0])
        XCTAssertEqual(bytes, Data([4, 5, 6]))
    }

    func testStaleRevisionDoesNotOverwriteNewerInk() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1
        let saved = try await workspace.save(page, drawing: Data([10]))
        do { _ = try await workspace.save(page, drawing: Data([99])); XCTFail("Stale save accepted") }
        catch WorkspaceFailure.staleRevision { }
        let ink = try await workspace.drawing(saved)
        XCTAssertEqual(ink, Data([10]))
    }

    func testRecoverySaveKeepsTheLastValidBackup() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([1]))
        let validBackup = page.drawingFile
        page.revision = 2; page = try await workspace.save(page, drawing: Data([2]))
        guard let missing = page.drawingFile, let backup = validBackup else { return XCTFail("Missing snapshot paths") }
        let missingURL = try await workspace.url(missing)
        try FileManager.default.removeItem(at: missingURL)
        page.revision = 3
        let recovered = try await workspace.save(page, drawing: Data([1]), recoveredFromPrevious: true)
        XCTAssertEqual(recovered.previousDrawingFile, backup)
        let backupURL = try await workspace.url(backup)
        XCTAssertEqual(try Data(contentsOf: backupURL), Data([1]))
    }

    func testPageOrderDuplicateAndDeletionPreserveOtherPages() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var original = try await workspace.addPage(); original.revision = 1
        original = try await workspace.save(original, drawing: Data([11]))
        let copy = try await workspace.duplicatePage(original.id)
        XCTAssertNotEqual(copy.id, original.id)
        let copied = try await workspace.drawing(copy)
        XCTAssertEqual(copied, Data([11]))
        try await workspace.movePage(copy.id, offset: -1)
        let order = try await workspace.pages().map(\.id)
        XCTAssertEqual(order, [copy.id, original.id])
        try await workspace.deletePage(original.id)
        let remaining = try await workspace.pages()
        XCTAssertEqual(remaining.map(\.id), [copy.id])
    }

    func testUnsafePathsAreRejected() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../Library.store", "/etc/passwd", "images/../../other", "C:\\other", "", "./manifest.json", "images//file", "images/\0file"] {
            do { _ = try await workspace.url(path); XCTFail("Unsafe path accepted: \(path)") }
            catch WorkspaceFailure.invalidPath { }
        }
    }

    func testValidNewFilesWithAndWithoutDirectoryTrailingSlash() async throws {
        let (root, store, manifest, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = store.packageURL(for: manifest.documentID)
        for isDirectory in [false, true] {
            let variant = DocumentWorkspace(package: URL(fileURLWithPath: directory.path, isDirectory: isDirectory),
                documentID: manifest.documentID, notebookID: manifest.notebookID)
            for name in ["drawings/new-\(isDirectory).drawing", "catalog-\(isDirectory).json"] {
                let url = try await variant.url(name)
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                try Data([7, 8, 9]).write(to: url, options: .atomic)
                XCTAssertEqual(try Data(contentsOf: url), Data([7, 8, 9]))
            }
        }
    }

    func testDarwinPrivateVarAliasAllowsNewFiles() async throws {
        let (root, store, manifest, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = store.packageURL(for: manifest.documentID).path
        let alternate: String
        if path.hasPrefix("/private/var/") { alternate = String(path.dropFirst("/private".count)) }
        else if path.hasPrefix("/var/") { alternate = "/private" + path }
        else { throw XCTSkip("This host does not use the Darwin /private/var alias.") }
        guard FileManager.default.fileExists(atPath: alternate) else { throw XCTSkip("Alias not present on this host.") }
        let workspace = DocumentWorkspace(package: URL(fileURLWithPath: alternate, isDirectory: true),
            documentID: manifest.documentID, notebookID: manifest.notebookID)
        let file = try await workspace.url("drawings/alias-check.drawing")
        try Data([42]).write(to: file, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: file), Data([42]))
    }

    func testSymlinksInsidePackageCannotEscapeIncludingDanglingLinks() async throws {
        let (root, store, manifest, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let package = store.packageURL(for: manifest.documentID)
        for (name, target) in [("existing", outside), ("dangling", root.appendingPathComponent("missing"))] {
            try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("drawings/\(name)"), withDestinationURL: target)
            do { _ = try await workspace.url("drawings/\(name)/escaped.drawing"); XCTFail("Symlink accepted") }
            catch WorkspaceFailure.invalidPath { }
        }
    }

    func testOlderAudioCheckpointCannotRegressFinalTimeline() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var early = AudioSession(title: "Lezione"); early.revision = 1
        early.segments = [AudioTimelineSegment(file: "audio/test.caf", start: 0, hostStart: 10)]
        early.segments[0].duration = 2
        try await workspace.saveSession(early)
        var completed = early; completed.revision = 2; completed.state = "finished"; completed.segments[0].duration = 10
        try await workspace.saveSession(completed)
        try await workspace.saveSession(early)
        let saved = try await workspace.catalog().sessions.first
        XCTAssertEqual(saved?.duration, 10)
        XCTAssertEqual(saved?.state, "finished")
    }

    func testCloneRemapsNotebookPageAndAudioIdentities() async throws {
        let (root, store, manifest, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AudioSession(title: "Lezione")
        try await workspace.saveSession(session)
        var page = try await workspace.addPage(); page.revision = 1
        page.anchors = [StrokeAnchor(signature: "stroke", audioSessionID: session.id, seconds: 4.5)]
        page = try await workspace.save(page, drawing: Data([42]))
        let newDocument = UUID(), newNotebook = UUID()
        try store.clone(from: workspace.package, documentID: newDocument, notebookID: newNotebook)
        let cloned = DocumentWorkspace(package: store.packageURL(for: newDocument), documentID: newDocument, notebookID: newNotebook)
        let pages = try await cloned.pages(), catalog = try await cloned.catalog()
        XCTAssertNotEqual(pages[0].id, page.id)
        XCTAssertNotEqual(catalog.sessions[0].id, session.id)
        XCTAssertEqual(pages[0].anchors[0].audioSessionID, catalog.sessions[0].id)
        let bytes = try await cloned.drawing(pages[0])
        XCTAssertEqual(bytes, Data([42]))
        XCTAssertNoThrow(try store.read(documentID: manifest.documentID, notebookID: manifest.notebookID))
    }
}
