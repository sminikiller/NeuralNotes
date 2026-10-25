import XCTest
import AVFoundation
import NeuralNotesCore
@testable import NeuralNotes

final class AudioTranscriptionTests: XCTestCase {
    @MainActor func testAudioFileImportRateAndBookmarkWithoutMicrophonePermission() async throws {
        let (workspace, root) = try makeWorkspace(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Lezione.caf"); try writeSilentAudio(source)
        let audio = AudioController(workspace: workspace); await audio.load(); await audio.importAudio(source)
        XCTAssertNil(audio.error)
        let session = try XCTUnwrap(audio.sessions.first)
        XCTAssertGreaterThan(session.duration, 0); XCTAssertEqual(session.state, "finished")
        audio.setPlaybackRate(1.5); XCTAssertEqual(audio.playbackRate, 1.5)
        audio.setPlaybackRate(.nan); XCTAssertEqual(audio.playbackRate, 1.5)
        await audio.addBookmark(sessionID: session.id)
        XCTAssertEqual(audio.sessions.first?.bookmarks?.count, 1)
        let bookmark = try XCTUnwrap(audio.sessions.first?.bookmarks?.first)
        await audio.removeBookmark(bookmark, sessionID: session.id)
        XCTAssertTrue(audio.sessions.first?.bookmarks?.isEmpty == true)
        await audio.close()
    }
    @MainActor
    func testRenamingLegacyTextWithAnEmptyChunkArrayDoesNotEraseIt() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
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
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
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
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
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
        XCTAssertNotEqual(saved.transcriptionComplete, true)
        XCTAssertTrue(first.transcriptionStatus.contains("2 blocchi da riprovare"))
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
    @MainActor
    func testWindowReaderDeliversEveryFrameWithoutExport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSilentAudio(url)
        let duration = try AudioWindowReader.duration(of: url)
        XCTAssertEqual(duration, 95, accuracy: 0.001)
        let frames = try SpeechWindow.plan(duration: duration, maximum: 45).map { window in
            try AudioWindowReader.read(url: url, window: window) { _ in }
        }
        XCTAssertEqual(frames, [720_000, 720_000, 80_000])
    }
    @MainActor
    func testLongRecordingSkipsFailedBlocksStaysCompactAndResumesOnlyThose() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = "audio/long.caf"; try writeSilentAudio(try await workspace.url(file), seconds: 160, rate: 8000)
        var segment = AudioTimelineSegment(file: file, start: 0, hostStart: 0); segment.duration = 160
        var session = AudioSession(title: "Lezione lunga"); session.state = "finished"; session.segments = [segment]
        try await workspace.saveSession(session)
        let audio = AudioController(workspace: workspace); await audio.load()
        // 160 blocks, like a two-hour lecture split into 45-second blocks.
        audio.transcriptionWindowLength = 1
        audio.windowRecognition = { _, window, _ in
            if window.start == 40 || window.start == 41 { throw NSError(domain: "Fixture", code: 7) }
            return (0..<12).map { TranscriptSegment(start: Double($0) * 0.08, duration: 0.06, text: "parola\($0)") }
        }
        audio.startTranscription(session); await audio.transcriptionTask?.value
        var catalog = try await workspace.catalog()
        var saved = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(saved.transcriptionChunks?.count, 158)
        XCTAssertNotEqual(saved.transcriptionComplete, true)
        XCTAssertTrue(audio.transcriptionStatus.contains("2 blocchi da riprovare"))
        // Twelve words per block are stored as one phrase, not twelve entries.
        XCTAssertEqual(saved.transcript.count, 158)
        let catalogFile = try await workspace.url("catalog.json")
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: catalogFile.path)[.size] as? Int)
        XCTAssertLessThan(size, 200_000)
        var requested: [Double] = []
        audio.windowRecognition = { _, window, _ in
            requested.append(window.start)
            return [TranscriptSegment(start: 0, duration: 0.5, text: "recuperato")]
        }
        audio.startTranscription(saved); await audio.transcriptionTask?.value
        catalog = try await workspace.catalog()
        saved = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(requested, [40, 41]); XCTAssertEqual(saved.transcriptionComplete, true)
        XCTAssertEqual(saved.transcriptionChunks?.count, 160)
        await audio.close()
    }
    @MainActor
    func testThreeConsecutiveFailedBlocksStopWithTheLastError() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = "audio/stop.caf"; try writeSilentAudio(try await workspace.url(file), seconds: 10, rate: 8000)
        var segment = AudioTimelineSegment(file: file, start: 0, hostStart: 0); segment.duration = 10
        var session = AudioSession(title: "Errori ripetuti"); session.state = "finished"; session.segments = [segment]
        try await workspace.saveSession(session)
        let audio = AudioController(workspace: workspace); await audio.load()
        audio.transcriptionWindowLength = 1
        var requested = 0
        audio.windowRecognition = { _, window, _ in
            requested += 1
            if window.start >= 3 { throw NSError(domain: "Fixture", code: 9) }
            return [TranscriptSegment(start: 0, duration: 0.5, text: "ok")]
        }
        audio.startTranscription(session); await audio.transcriptionTask?.value
        let catalog = try await workspace.catalog()
        let saved = try XCTUnwrap(catalog.sessions.first)
        XCTAssertEqual(saved.transcriptionChunks?.count, 3); XCTAssertNotEqual(saved.transcriptionComplete, true)
        XCTAssertEqual(requested, 9)
        XCTAssertTrue(audio.error?.contains("tre blocchi consecutivi") == true)
        await audio.close()
    }
    @MainActor
    func testSixHourFilePipelineResumesAfterCancellationAndKeepsCorrections() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "audio/six-hours.wav", url = try await workspace.url(path)
        // A sparse PCM file has a real six-hour header and readable frames,
        // without writing hundreds of MB of zeroes into the test fixture.
        try writeSparseWave(url, seconds: 21600)
        XCTAssertEqual(try AudioWindowReader.duration(of: url), 21600, accuracy: 0.001)
        let lastWindow = try XCTUnwrap(SpeechWindow.plan(duration: 21600, maximum: 45).last)
        XCTAssertEqual(try AudioWindowReader.read(url: url, window: lastWindow) { _ in }, 360_000)
        // Historical documents may contain a device-clock stamp. Windowing and
        // resume must depend exclusively on the session-relative timeline.
        var part = AudioTimelineSegment(file: path, start: 0, hostStart: 900_000); part.duration = 21600
        var session = AudioSession(title: "Sei ore"); session.state = "finished"; session.segments = [part]
        try await workspace.saveSession(session)
        let first = AudioController(workspace: workspace); await first.load()
        first.windowRecognition = { _, window, _ in
            if window.start >= 5400 { throw CancellationError() }
            return [TranscriptSegment(start: 1, duration: 1, text: "Blocco \(Int(window.start))")]
        }
        first.startTranscription(session); await first.transcriptionTask?.value
        let checkpoint = try await workspace.catalog()
        let saved = try XCTUnwrap(checkpoint.sessions.first)
        XCTAssertEqual(saved.transcriptionChunks?.count, 120)
        XCTAssertNotEqual(saved.transcriptionComplete, true)
        var blocks = TranscriptText.minutes(saved.readableTranscript); blocks[0].text = "Correzione conservata"
        try await first.saveTranscript(session.id, title: "Lezione completa", blocks: blocks)
        await first.close()
        let second = AudioController(workspace: workspace); await second.load()
        var requested: [Double] = []
        second.windowRecognition = { _, window, language in
            XCTAssertEqual(language, "it-IT"); requested.append(window.start)
            return [TranscriptSegment(start: 1, duration: 1, text: "Blocco \(Int(window.start))")]
        }
        let reopened = try XCTUnwrap(second.sessions.first)
        second.startTranscription(reopened); await second.transcriptionTask?.value
        let finalCatalog = try await workspace.catalog(), final = try XCTUnwrap(finalCatalog.sessions.first)
        XCTAssertNil(second.error); XCTAssertEqual(requested.count, 360); XCTAssertEqual(requested.first, 5400)
        XCTAssertEqual(requested.last, 21555); XCTAssertEqual(final.transcriptionChunks?.count, 480)
        XCTAssertTrue(final.hasCompletedTranscript); XCTAssertEqual(final.title, "Lezione completa")
        XCTAssertEqual(final.readableTranscript.last?.start, 21556)
        XCTAssertTrue(final.readableTranscript.contains { $0.text.contains("Correzione conservata") })
        let exported = TranscriptText.export(title: final.title, segments: final.readableTranscript, complete: final.hasCompletedTranscript)
        XCTAssertTrue(exported.contains("05:59:00")); XCTAssertTrue(exported.contains("Blocco 21555"))
        await second.close()
        // Recognition is injected: this exercises the Apple controller and IO,
        // not Speech accuracy, recording hardware, or six hours in standby.
    }
    func testSilenceErrorIsAnEmptyBlockNotAFailure() {
        let silence = NSError(domain: "kAFAssistantErrorDomain", code: 1110, userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        XCTAssertTrue(AppleTranscriptionService.isNoSpeech(silence))
        XCTAssertFalse(AppleTranscriptionService.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1101)))
        XCTAssertTrue(AppleTranscriptionService.describe(NSError(domain: "Fixture", code: 4)).contains("Fixture 4"))
    }

    private func makeWorkspace() throws -> (DocumentWorkspace, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        return (workspace, root)
    }

    private func writeSilentAudio(_ url: URL, seconds: Int = 95, rate: Double = 16000) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(rate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData); samples[0].initialize(repeating: 0, count: Int(frames))
        for _ in 0..<seconds { try file.write(from: buffer) }
    }
    private func writeSparseWave(_ url: URL, seconds: UInt32) throws {
        let rate: UInt32 = 8000, bytes: UInt32 = seconds * rate * 2
        var header = Data("RIFF".utf8)
        func append16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { header.append(contentsOf: $0) } }
        func append32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { header.append(contentsOf: $0) } }
        append32(bytes + 36); header.append(Data("WAVEfmt ".utf8)); append32(16)
        append16(1); append16(1); append32(rate); append32(rate * 2); append16(2); append16(16)
        header.append(Data("data".utf8)); append32(bytes)
        try header.write(to: url)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        try output.seek(toOffset: UInt64(44) + UInt64(bytes) - 1); try output.write(contentsOf: Data([0])); try output.synchronize()
    }
}
