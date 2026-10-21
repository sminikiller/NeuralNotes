import XCTest
@testable import NeuralNotesCore

final class AudioLibraryExportTests: XCTestCase {
    private func fixture() async throws -> (URL, DocumentWorkspace, AudioSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let writer = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        _ = try await writer.addPage()
        var session = AudioSession(title: "Lezione di fisica"); session.state = "finished"; session.revision = 1
        for i in 0..<2 {
            let path = "audio/part-\(i).caf"; try Data(repeating: UInt8(i + 1), count: 1_100_000).write(to: await writer.url(path))
            var part = AudioTimelineSegment(file: path, start: Double(i) * 10800, hostStart: 0); part.duration = 10800; session.segments.append(part)
        }
        session.transcript = [TranscriptSegment(start: 1, duration: 1, text: "Prima"), TranscriptSegment(start: 21590, duration: 1, text: "Fine della lezione")]
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: "Correzione conservata")]; session.transcriptionComplete = true
        try await writer.saveSession(session); return (root, writer, session)
    }
    func testExportCopiesAllSixHourPartsAndCorrectedTranscriptWithoutChangingOriginals() async throws {
        let (root, writer, session) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try await writer.exportAudioSession(session.id); defer { try? bundle.removeTemporaryFiles() }
        XCTAssertEqual(bundle.files.count, 6)
        let parts = bundle.files.filter { $0.pathExtension == "caf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(parts.count, 2)
        for i in 0..<2 { XCTAssertEqual(try Data(contentsOf: parts[i]), Data(repeating: UInt8(i + 1), count: 1_100_000)) }
        let text = try String(contentsOf: bundle.directory.appendingPathComponent("Trascrizione.txt"), encoding: .utf8)
        XCTAssertTrue(text.contains("Correzione conservata")); XCTAssertTrue(text.contains("Fine della lezione")); XCTAssertTrue(text.contains("05:59:00"))
        let playlist = try String(contentsOf: bundle.directory.appendingPathComponent("Registrazione.m3u8"), encoding: .utf8)
        XCTAssertTrue(playlist.contains(parts[0].lastPathComponent)); XCTAssertTrue(playlist.contains(parts[1].lastPathComponent))
        let reopened = try await writer.catalog().sessions.first; XCTAssertEqual(reopened?.segments, session.segments)
        for part in session.segments { XCTAssertTrue(FileManager.default.fileExists(atPath: writer.package.appendingPathComponent(part.file).path)) }
        _ = try NativePackageInspector.inspect(writer.package)
    }
    func testArchiveTrashRestoreAndTranscriptDeletionPreserveRecordingAndAnchors() async throws {
        let (root, writer, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let pages = try await writer.pages(); var page = try XCTUnwrap(pages.first); page.revision += 1
        page.anchors = [StrokeAnchor(signature: "fixture", audioSessionID: original.id, seconds: 5)]
        _ = try await writer.save(page, drawing: Data([1]))
        var value = try await writer.changeAudioSession(original.id, expectedRevision: 1, action: .archive(true))
        value = try await writer.changeAudioSession(value.id, expectedRevision: value.revision!, action: .trash)
        XCTAssertNotNil(value.trashedAt); XCTAssertTrue(AudioLibraryQuery.sessions([value], scope: .recent).isEmpty)
        XCTAssertEqual(AudioLibraryQuery.sessions([value], scope: .trash).count, 1)
        let hidden = try await writer.indexedChunks(); XCTAssertFalse(hidden.contains { $0.kind == .audio })
        value = try await writer.changeAudioSession(value.id, expectedRevision: value.revision!, action: .restore)
        XCTAssertEqual(AudioLibraryQuery.sessions([value], scope: .archived).count, 1)
        let searchable = try await writer.indexedChunks(); XCTAssertTrue(searchable.contains { $0.kind == .audio && $0.text.contains("Fine della lezione") })
        value = try await writer.changeAudioSession(value.id, expectedRevision: value.revision!, action: .rename("Esame"))
        value = try await writer.changeAudioSession(value.id, expectedRevision: value.revision!, action: .clearTranscript)
        XCTAssertEqual(value.title, "Esame"); XCTAssertFalse(value.hasTranscriptText); XCTAssertNil(value.transcriptionComplete); XCTAssertNil(value.transcriptCorrections)
        XCTAssertEqual(value.segments, original.segments)
        let savedPage = try await writer.pageSnapshot(page.id); XCTAssertEqual(savedPage.anchors, page.anchors)
        do { _ = try await writer.changeAudioSession(value.id, expectedRevision: 1, action: .trash); XCTFail("Stale operation applied") } catch WorkspaceFailure.staleRevision { }
        _ = try NativePackageInspector.inspect(writer.package)
    }
    func testAudioQueryHasStableChronologyAndSeparateArchiveAndTrash() {
        var old = AudioSession(title: "Matematica"), recent = AudioSession(title: "Fisica")
        old.createdAt = Date(timeIntervalSince1970: 1); recent.createdAt = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(AudioLibraryQuery.sessions([old, recent], scope: .recent).map(\.id), [recent.id, old.id])
        XCTAssertEqual(AudioLibraryQuery.sessions([recent, old], scope: .recent, query: "FISICA").map(\.id), [recent.id])
        recent.isArchived = true; XCTAssertEqual(AudioLibraryQuery.sessions([recent, old], scope: .archived).map(\.id), [recent.id])
        recent.trashedAt = .now; XCTAssertTrue(AudioLibraryQuery.sessions([recent, old], scope: .archived).isEmpty)
    }
    func testExportRejectsMissingMediaAndUnfinishedRecordings() async throws {
        let (root, writer, session) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: writer.package.appendingPathComponent(session.segments[1].file))
        do { _ = try await writer.exportAudioSession(session.id); XCTFail("Incomplete export returned") } catch { }
        var unfinished = session; unfinished.id = UUID(); unfinished.state = "recording"; try await writer.saveSession(unfinished)
        do { _ = try await writer.exportAudioSession(unfinished.id); XCTFail("Live recorder exported") } catch WorkspaceFailure.staleRevision { }
    }
    func testEightHourCheckpointSequenceResumesWithoutLosingTheEndOrCorrections() async throws {
        let (root, writer, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var session = original; session.segments[0].duration = 28800; session.segments.removeLast()
        session.transcriptionComplete = false; session.transcript = []; session.transcriptionChunks = []
        let windows = SpeechWindow.plan(duration: 28800, maximum: 45)
        XCTAssertEqual(windows.count, 640)
        func append(_ window: SpeechWindow, to value: inout AudioSession) {
            let text = TranscriptSegment(start: window.start, duration: 1, text: "Blocco a \(Int(window.start))")
            value.transcriptionChunks?.append(TranscriptionChunk(file: value.segments[0].file, window: window, language: "it-IT", segments: [text]))
            value.transcript.append(text); value.revision = (value.revision ?? 0) + 1
        }
        // Synthetic recognition/checkpoint workload; not an Apple Speech test.
        for window in windows.prefix(120) { append(window, to: &session); try await writer.saveSession(session) }
        let reopened = DocumentWorkspace(package: writer.package, documentID: writer.documentID, notebookID: try await writer.manifest().notebookID)
        let checkpoint = try await reopened.catalog(); session = try XCTUnwrap(checkpoint.sessions.first)
        XCTAssertEqual(session.transcriptionChunks?.count, 120)
        let completed = session.transcriptionChunks?.map(\.window) ?? []
        for window in windows where !completed.contains(window) { append(window, to: &session); try await reopened.saveSession(session) }
        session.transcriptionComplete = true; session.revision = (session.revision ?? 0) + 1; try await reopened.saveSession(session)
        let finalCatalog = try await reopened.catalog(); let final = try XCTUnwrap(finalCatalog.sessions.first)
        XCTAssertEqual(final.transcriptionChunks?.count, 640); XCTAssertTrue(final.hasCompletedTranscript)
        XCTAssertEqual(final.readableTranscript.last?.start, 28755); XCTAssertTrue(final.readableTranscript.contains { $0.text.contains("Correzione conservata") })
    }
}
