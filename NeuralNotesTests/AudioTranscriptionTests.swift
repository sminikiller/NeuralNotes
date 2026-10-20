import XCTest
import AVFoundation
import NeuralNotesCore
@testable import NeuralNotes

final class AudioTranscriptionTests: XCTestCase {
    @MainActor
    func testRenamingLegacyTextWithAnEmptyChunkArrayDoesNotEraseIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var session = AudioSession(title: "Prima"); session.state = "finished"; session.transcriptionComplete = true
        session.transcriptionChunks = []; session.transcript = [TranscriptSegment(start: 1, duration: 2, text: "Da conservare")]
        try await workspace.saveSession(session)
        let audio = AudioController(workspace: workspace); await audio.load()
        try await audio.saveTranscript(session.id, title: "Dopo", blocks: TranscriptText.minutes(session.readableTranscript))
        let catalog = try await workspace.catalog(), saved = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(saved.title, "Dopo"); XCTAssertEqual(saved.readableTranscript.map(\.text), ["Da conservare"])
        XCTAssertTrue(saved.hasCompletedTranscript)
        await audio.close()
    }
    @MainActor
    func testEmptyCompletedRecognitionCanRetryAllEmptyWindows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let file = "audio/empty.caf"; try writeSilentAudio(try await workspace.url(file))
        var segment = AudioTimelineSegment(file: file, start: 0, hostStart: 0); segment.duration = 95
        var session = AudioSession(title: "Riprova"); session.state = "finished"; session.segments = [segment]
        try await workspace.saveSession(session)
        let audio = AudioController(workspace: workspace); await audio.load()
        audio.windowRecognition = { _, _, _ in [] }
        audio.startTranscription(session); await audio.transcriptionTask?.value
        let empty = try XCTUnwrap(audio.sessions.first)
        XCTAssertEqual(empty.transcriptionComplete, true); XCTAssertFalse(empty.hasCompletedTranscript)
        XCTAssertTrue(audio.transcriptionStatus.contains("senza testo"))
        var requested: [Double] = []
        audio.windowRecognition = { _, window, _ in
            requested.append(window.start)
            return [TranscriptSegment(start: 1, duration: 1, text: "Riconosciuto")]
        }
        audio.startTranscription(empty); await audio.transcriptionTask?.value
        XCTAssertEqual(requested, [0, 45, 90]); XCTAssertEqual(audio.sessions.first?.hasCompletedTranscript, true)
        let catalog = try await workspace.catalog()
        XCTAssertEqual(catalog.sessions.first?.readableTranscript.count, 3)
        await audio.close()
    }
    @MainActor
    func testFailedWindowResumesAfterControllerRecreationAndKeepsManualCorrections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let file = "audio/control.caf", url = try await workspace.url(file)
        try writeSilentAudio(url)
        var segment = AudioTimelineSegment(file: file, start: 70, hostStart: 0); segment.duration = 95
        var session = AudioSession(title: "Originale"); session.state = "finished"; session.segments = [segment]
        try await workspace.saveSession(session)
        let first = AudioController(workspace: workspace); await first.load()
        // The fixture checks IO/resume. It never calls Apple Speech or claims ASR accuracy.
        first.windowRecognition = { _, window, _ in
            if window.start > 0 { throw NSError(domain: "Fixture", code: 1) }
            return [TranscriptSegment(start: 1, duration: 1, text: "Originale")]
        }
        first.startTranscription(session); await first.transcriptionTask?.value
        var catalog = try await workspace.catalog()
        var saved = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(saved.transcriptionChunks?.count, 1); XCTAssertEqual(saved.transcript.first?.start, 71)
        var blocks = TranscriptText.minutes(saved.transcript); blocks[0].text = "Correzione manuale"
        try await first.saveTranscript(session.id, title: "Lezione rinominata", blocks: blocks)
        await first.close()
        let second = AudioController(workspace: workspace); await second.load()
        var requested: [Double] = []
        second.windowRecognition = { _, window, _ in
            requested.append(window.start)
            return [TranscriptSegment(start: 1, duration: 1, text: "Nuovo blocco")]
        }
        catalog = try await workspace.catalog()
        saved = try XCTUnwrap(catalog.sessions.first)
        second.startTranscription(saved); await second.transcriptionTask?.value
        let finalCatalog = try await workspace.catalog()
        let final = try XCTUnwrap(finalCatalog.sessions.first)
        XCTAssertEqual(requested, [45, 90]); XCTAssertEqual(final.transcriptionComplete, true)
        XCTAssertEqual(final.title, "Lezione rinominata"); XCTAssertEqual(final.transcript.first?.text, "Correzione manuale")
        XCTAssertEqual(final.transcriptionChunks?.count, 3)
        await second.close()
    }

    private func writeSilentAudio(_ url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16000))
        buffer.frameLength = 16000
        let samples = try XCTUnwrap(buffer.floatChannelData); samples[0].initialize(repeating: 0, count: 16000)
        for _ in 0..<95 { try file.write(from: buffer) }
    }
}
