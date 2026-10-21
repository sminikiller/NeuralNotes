import XCTest
@testable import NeuralNotesCore

final class AudioCompressionJournalTests: XCTestCase {
    private func fixture() async throws -> (URL, DocumentWorkspace, AudioSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var session = AudioSession(title: "Lezione"); session.revision = 0
        for i in 0..<2 {
            let path = "audio/part-\(i).caf"; try Data(repeating: 1, count: 4000).write(to: await workspace.url(path))
            var part = AudioTimelineSegment(file: path, start: Double(i), hostStart: 10 + Double(i)); part.duration = 1; session.segments.append(part)
        }
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: "Correzione")]
        session.transcriptionChunks = [TranscriptionChunk(file: session.segments[0].file, window: SpeechWindow(start: 0, duration: 1), language: "it-IT", segments: [TranscriptSegment(start: 0.2, duration: 0.2, text: "Parola")])]
        try await workspace.saveSession(session)
        session.state = "finished"; session.revision = 1; try await workspace.saveSession(session)
        var page = PageSnapshot(); page.anchors = [StrokeAnchor(signature: "ink", audioSessionID: session.id, seconds: 0.4)]; _ = try await workspace.addPage(page)
        return (root, workspace, session)
    }
    private func verify(_ part: AudioCompressionPart, plan: AudioCompressionPlan, workspace: DocumentWorkspace) async throws {
        // Metadata/transaction fixture only. Native tests exercise the AAC codec.
        try Data(repeating: 2, count: 100).write(to: await workspace.url(part.destination))
        _ = try await workspace.verifyAudioCompressionPart(plan.id, destination: part.destination, verification: AudioCompressionVerification(sourceFrames: 44100, sourceRate: 44100, decodedFrames: 44100, decodedRate: 44100, encodedBytes: 100))
    }
    func testInterruptedPreparationResumesAndCommitsBothCatalogsBeforeRemovingPCM() async throws {
        let (root, workspace, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try await workspace.beginAudioCompression(original.id, sources: original.segments.map(\.file))
        try await verify(plan.parts[0], plan: plan, workspace: workspace)
        let report = try await workspace.storageReport()
        XCTAssertFalse(report.unusedFiles.contains(plan.parts[0].destination))
        let reopened = DocumentWorkspace(package: workspace.package, documentID: workspace.documentID, notebookID: try await workspace.manifest().notebookID)
        let pending = try await reopened.pendingAudioCompression(); XCTAssertNotNil(pending?.parts[0].verification); XCTAssertNil(pending?.parts[1].verification)
        let before = try await reopened.catalog(); XCTAssertEqual(before.sessions.first?.segments, original.segments)
        try await verify(plan.parts[1], plan: plan, workspace: reopened)
        let removed = try await reopened.commitAudioCompression(plan.id); XCTAssertEqual(removed, 8000)
        let catalog = try await reopened.catalog(), session = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(session.segments.map(\.start), original.segments.map(\.start)); XCTAssertEqual(session.segments.map(\.duration), original.segments.map(\.duration))
        XCTAssertEqual(session.transcriptionChunks?.first?.file, plan.parts[0].destination); XCTAssertEqual(session.transcriptCorrections, original.transcriptCorrections)
        let pages = try await reopened.pages(); XCTAssertEqual(pages.first?.anchors.first?.seconds, 0.4)
        XCTAssertTrue(session.segments.allSatisfy { $0.codec == "aac" && $0.bitRate == 64000 })
        for source in original.segments { XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(source.file).path)) }
        _ = try CatalogRecovery.read(CatalogRecovery.previousPath, package: workspace.package, requireMedia: true)
        _ = try NativePackageInspector.inspect(workspace.package)
        let cleared = try await reopened.pendingAudioCompression(); XCTAssertNil(cleared)
        let manifest = try await reopened.manifest()
        let book = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "AAC", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let backup = try await reopened.exportNative(metadata: book)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restoredURL = root.appendingPathComponent("AAC-restored")
        try NativeArchive.extract(from: backup, to: restoredURL)
        let inspected = try NativePackageInspector.inspect(restoredURL)
        let restored = DocumentWorkspace(package: restoredURL, documentID: inspected.manifest.documentID, notebookID: inspected.manifest.notebookID)
        let restoredCatalog = try await restored.catalog(); XCTAssertEqual(restoredCatalog.sessions.first?.segments, session.segments)
        let export = try await restored.exportAudioSession(original.id); defer { try? export.removeTemporaryFiles() }
        XCTAssertEqual(export.files.filter { $0.pathExtension == "m4a" }.count, 2)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: try XCTUnwrap(export.files.first(where: { $0.pathExtension == "json" })))) as? [String: Any]
        XCTAssertEqual(json?["format"] as? Int, 2)
    }
    func testCrashAfterReferenceSwitchIsDetectedWithoutRequiringDeletedSourceFiles() async throws {
        let (root, workspace, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try await workspace.beginAudioCompression(original.id, sources: original.segments.map(\.file))
        for part in plan.parts { try await verify(part, plan: plan, workspace: workspace) }
        var switched = original; switched.revision = 2
        for i in switched.segments.indices {
            switched.segments[i].file = plan.parts[i].destination; switched.segments[i].codec = "aac"; switched.segments[i].bitRate = 64000; switched.segments[i].originalBytes = plan.parts[i].sourceBytes
        }
        switched.transcriptionChunks?[0].file = plan.parts[0].destination
        try await workspace.saveSession(switched)
        // Exact crash boundary: catalog committed, journal still says preparing.
        try FileManager.default.removeItem(at: await workspace.url(original.segments[0].file))
        let reopened = DocumentWorkspace(package: workspace.package, documentID: workspace.documentID, notebookID: try await workspace.manifest().notebookID)
        _ = try await reopened.commitAudioCompression(plan.id)
        let final = try await reopened.catalog(); XCTAssertEqual(final.sessions.first?.segments, switched.segments)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
    func testTimingMismatchCannotSwitchReferencesAndPendingCompressionBlocksBackup() async throws {
        let (root, workspace, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try await workspace.beginAudioCompression(original.id, sources: original.segments.map(\.file))
        try Data(repeating: 2, count: 100).write(to: await workspace.url(plan.parts[0].destination))
        let bad = AudioCompressionVerification(sourceFrames: 44100, sourceRate: 44100, decodedFrames: 48510, decodedRate: 44100, encodedBytes: 100)
        XCTAssertFalse(bad.isValid)
        do { _ = try await workspace.verifyAudioCompressionPart(plan.id, destination: plan.parts[0].destination, verification: bad); XCTFail("Drift accepted") } catch { }
        let before = try await workspace.catalog(); XCTAssertEqual(before.sessions.first?.segments, original.segments)
        let manifest = try await workspace.manifest(), book = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Lezione", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let skipped = try await workspace.createAutomaticBackup(metadata: book, minimumInterval: 0); XCTAssertNil(skipped)
        do { _ = try await workspace.exportNative(metadata: book); XCTFail("Pending conversion archived") } catch { }
        for source in original.segments { XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(source.file).path)) }
    }
    func testAbortingPreparationRemovesOnlyItsUnreferencedOutputsAndRestoresBackupAvailability() async throws {
        let (root, workspace, original) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try await workspace.beginAudioCompression(original.id, sources: original.segments.map(\.file))
        try await verify(plan.parts[0], plan: plan, workspace: workspace)
        try Data([3]).write(to: await workspace.url(plan.parts[1].destination))
        try await workspace.discardAudioCompression(plan.id)
        let pending = try await workspace.pendingAudioCompression(); XCTAssertNil(pending)
        let catalog = try await workspace.catalog(); XCTAssertEqual(catalog.sessions.first?.segments, original.segments)
        for part in plan.parts {
            XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(part.source).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.package.appendingPathComponent(part.destination).path))
        }
        _ = try NativePackageInspector.inspect(workspace.package)
    }
}
