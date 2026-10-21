import Foundation
import XCTest
@testable import NeuralNotesCore

final class DocumentWorkspaceTests: XCTestCase {
    func testOversizedButOtherwiseValidPageIsRejectedWithoutRewritingIt() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage(), file = workspace.package.appendingPathComponent("pages/\(page.id).json")
        let original = try Data(contentsOf: file), padding = Data(repeating: 32, count: 16 * 1024 * 1024)
        try (original + padding).write(to: file)
        do { _ = try await workspace.pageSnapshot(page.id); XCTFail("Oversized page read") } catch NativeArchiveFailure.limit { }
        XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, original.count + padding.count)
    }
    func testOversizedDrawingAndImageLeaveTheLastReadableNotebookUntouched() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([42]))
        let before = try Data(contentsOf: workspace.package.appendingPathComponent("pages/\(page.id).json"))
        let images = try FileManager.default.contentsOfDirectory(atPath: workspace.package.appendingPathComponent("images").path)
        let tooLarge = Data(count: 100 * 1024 * 1024 + 1)
        var changed = page; changed.revision += 1
        do { _ = try await workspace.save(changed, drawing: tooLarge); XCTFail("Unexportable drawing accepted") }
        catch WorkspaceFailure.oversizedImport { }
        do { _ = try await workspace.storeImage(tooLarge); XCTFail("Unexportable image accepted") }
        catch WorkspaceFailure.oversizedImport { }
        XCTAssertEqual(try Data(contentsOf: workspace.package.appendingPathComponent("pages/\(page.id).json")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.package.appendingPathComponent("images").path), images)
        let bytes = try await workspace.drawing(page); XCTAssertEqual(bytes, Data([42]))
        XCTAssertNoThrow(try NativePackageInspector.inspect(workspace.package))
    }
    func testGlossaryAndBoundedSelectionCacheSurviveReopenAndEnterSearch() async throws {
        let (root, _, manifest, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage(), reference = SourceReference(documentID: manifest.documentID)
        let entry = GlossaryEntry(term: "Entropia", definition: "Definizione rivista", references: [reference])
        try await workspace.saveGlossaryEntry(entry)
        for i in 0..<35 {
            let key = String(format: "%064x", i)
            try await workspace.cacheLensAnswer(key: key, artifact: AIArtifact(text: "Risposta \(i)", references: [reference], provider: "fixture"))
        }
        let catalog = try await workspace.catalog(); XCTAssertEqual(catalog.glossary?.first?.id, entry.id); XCTAssertEqual(catalog.glossary?.first?.definition, entry.definition)
        XCTAssertEqual(catalog.glossary?.first?.updatedAt.timeIntervalSince1970 ?? 0, entry.updatedAt.timeIntervalSince1970, accuracy: 1); XCTAssertEqual(catalog.lensCache?.count, 32)
        let absent = try await workspace.cachedLensAnswer(key: String(format: "%064x", 0)); XCTAssertNil(absent)
        let present = try await workspace.cachedLensAnswer(key: String(format: "%064x", 34)); XCTAssertEqual(present?.text, "Risposta 34")
        let chunks = try await workspace.indexedChunks(); XCTAssertTrue(chunks.contains { $0.text.contains("Entropia") })
        XCTAssertNoThrow(try NativePackageInspector.inspect(workspace.package))
        var invalid = entry; invalid.term = ""
        do { try await workspace.saveGlossaryEntry(invalid); XCTFail("Empty term accepted") } catch { }
        try await workspace.removeGlossaryEntry(entry.id)
        let remaining = try await workspace.catalog().glossary; XCTAssertTrue(remaining?.isEmpty == true)
        let pages = try await workspace.pages(); XCTAssertEqual(page.id, pages.first?.id)
    }
    func testOrganizationTravelsWithNativeNotebookAndValidatesTags() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        var organization = NotebookOrganization()
        organization.tags = NotebookOrganization.tags(from: " Matematica, esame , MATEMATICA, "); organization.pinned = true; organization.inbox = true
        XCTAssertEqual(organization.tags, ["matematica", "esame"])
        try await workspace.setOrganization(organization)
        let value = try await workspace.catalog().organization; XCTAssertEqual(value, organization)
        XCTAssertNoThrow(try NativePackageInspector.inspect(workspace.package))
        organization.tags = [String(repeating: "x", count: 33)]
        do { try await workspace.setOrganization(organization); XCTFail("Invalid tag accepted") } catch { }
        let unchanged = try await workspace.catalog().organization; XCTAssertEqual(unchanged, value)
    }
    func testImportedAudioIsAnIndependentFileAndBookmarksSurviveReopen() async throws {
        let (root, _, _, workspace) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await workspace.addPage()
        let source = root.appendingPathComponent("lecture.wav"), bytes = Data(repeating: 7, count: 2_100_000)
        try bytes.write(to: source)
        var session = try await workspace.importAudio(from: source, duration: 3600, title: "Lezione")
        XCTAssertEqual(session.duration, 3600); XCTAssertEqual(session.state, "finished")
        try Data([8]).write(to: source)
        let copied = try await workspace.url(session.segments[0].file)
        XCTAssertEqual(try Data(contentsOf: copied), bytes)
        session.bookmarks = [AudioBookmark(title: "Definizione", seconds: 123)]; session.revision = 2
        try await workspace.saveSession(session)
        let catalog = try await workspace.catalog(); XCTAssertEqual(catalog.sessions.first?.bookmarks?.first?.seconds, 123)
        XCTAssertNoThrow(try NativePackageInspector.inspect(workspace.package))
        do { _ = try await workspace.importAudio(from: source, duration: .nan, title: "No"); XCTFail("Invalid duration accepted") } catch { }
    }
    func testReplayOnlyFiltersStrokesLinkedToThePlayingSession() {
        let session = UUID(), other = UUID()
        let anchors = [StrokeAnchor(signature: "a", audioSessionID: session, seconds: 4), StrokeAnchor(signature: "b", audioSessionID: other, seconds: 100), StrokeAnchor(signature: "c", audioSessionID: session, seconds: 10)]
        XCTAssertEqual(AudioReplay.visible(signatures: ["a", "b", "c", "free"], anchors: anchors, sessionID: session, seconds: 5), [0, 1, 3])
        XCTAssertEqual(AudioReplay.visible(signatures: ["a", "b", "c", "free"], anchors: anchors, sessionID: session, seconds: 10), [0, 1, 2, 3])
        XCTAssertEqual(AudioReplay.visible(signatures: ["a", "b", "c", "free"], anchors: anchors, sessionID: session, seconds: 0), [1, 3])
    }
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

    func testLatestEditKeepsSubsecondPrecisionAndIgnoresPageOrderAndDeletedPages() async throws {
        let (root, store, manifest, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var first = PageSnapshot(); first.lastEditedAt = 100.1
        var second = PageSnapshot(); second.lastEditedAt = 100.2
        _ = try await workspace.addPage(first); _ = try await workspace.addPage(second)
        _ = try await workspace.addPage()
        try await workspace.movePage(second.id, offset: -1)
        let reopened = DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
            documentID: manifest.documentID, notebookID: manifest.notebookID)
        let latest = try await reopened.lastEditedPage()
        XCTAssertEqual(latest?.id, second.id); XCTAssertEqual(latest?.lastEditedAt, 100.2)
        try await reopened.deletePage(second.id)
        let remaining = try await reopened.lastEditedPage()
        XCTAssertEqual(remaining?.id, first.id)
    }

    func testSavingAndPageDetailsCommitAnEditDateButReadingDoesNot() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var page = try await workspace.addPage()
        let before = try await workspace.lastEditedPage(); XCTAssertNil(before)
        page.revision = 1
        let start = Date().timeIntervalSince1970
        page = try await workspace.save(page, drawing: Data([1]))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(page.lastEditedAt), start)
        _ = try await workspace.drawing(page); _ = try await workspace.pages()
        let unchanged = try await workspace.lastEditedPage()
        XCTAssertEqual(unchanged?.lastEditedAt, page.lastEditedAt)
        let renamed = try await workspace.setPageDetails(page.id, title: "Titolo", bookmarked: true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(renamed.lastEditedAt), try XCTUnwrap(page.lastEditedAt))
    }

    func testCoverPreviewCanBeDisabledWithoutLosingTheCustomPhoto() async throws {
        let (root, _, _, workspace) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = Data([1, 2, 3])
        try await workspace.setCoverAppearance(image: photo, design: CoverDesign(), useLastEditedPage: true)
        // Existing callers that only change the design preserve the selected mode.
        try await workspace.setCoverAppearance(image: photo, design: CoverDesign())
        let active = try await workspace.catalog(); XCTAssertEqual(active.coverUsesLastEditedPage, true)
        try await workspace.setCoverAppearance(image: photo, design: CoverDesign(), useLastEditedPage: false)
        let custom = try await workspace.catalog(); XCTAssertEqual(custom.coverUsesLastEditedPage, false)
        let file = try await workspace.url(try XCTUnwrap(custom.coverImageFile))
        XCTAssertEqual(try Data(contentsOf: file), photo)
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
