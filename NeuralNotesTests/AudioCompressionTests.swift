import XCTest
import AVFoundation
import NeuralNotesCore
@testable import NeuralNotes

final class AudioCompressionTests: XCTestCase {
    func testSyntheticPCMConvertsToAACAndReadsFirstEndAndPartialBuffers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.caf"), output = root.appendingPathComponent("result.m4a")
        try writePCM(source)
        let check = try AudioCompression.encode(source: source, destination: output)
        XCTAssertTrue(check.isValid); XCTAssertEqual(check.duration, 3.25, accuracy: 0.0001)
        XCTAssertLessThan(abs(Double(check.decodedFrames) / check.decodedRate - check.duration), 0.05)
        XCTAssertLessThan(check.encodedBytes, Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
        XCTAssertFalse(AudioCompression.isPCM(output))
        var sizes: [UInt32] = []
        let frames = try AudioWindowReader.read(url: output, window: SpeechWindow(start: 0, duration: 0.1), chunk: 1024) { sizes.append($0.frameLength) }
        XCTAssertEqual(frames, 4410); XCTAssertTrue(sizes.allSatisfy { $0 <= 1024 }); XCTAssertLessThan(try XCTUnwrap(sizes.last), 1024)
        sizes = []
        let last = try AudioWindowReader.read(url: output, window: SpeechWindow(start: 3, duration: 1), chunk: 4096) { sizes.append($0.frameLength) }
        XCTAssertEqual(last, check.decodedFrames - 132300)
        XCTAssertTrue(sizes.allSatisfy { $0 <= 4096 }); XCTAssertGreaterThan(last, 0)
        XCTAssertLessThan(try XCTUnwrap(sizes.last), 4096)
        for start in [0.1, 2.9] {
            let pcm = try onset(source, window: SpeechWindow(start: start, duration: 0.35))
            let aac = try onset(output, window: SpeechWindow(start: start, duration: 0.35))
            XCTAssertEqual(pcm, aac, accuracy: 0.05, "AAC attack must remain aligned with page/audio anchors")
        }
        XCTAssertThrowsError(try AudioCompression.encode(source: source, destination: output))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor func testCompressedSessionResumesMockTranscriptionWithOriginalWindowTimes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let path = "audio/synthetic.caf", source = try await workspace.url(path); try writePCM(source)
        var session = AudioSession(title: "Lezione AAC"); session.state = "finished"
        var part = AudioTimelineSegment(file: path, start: 0, hostStart: 10); part.duration = 3.25; session.segments = [part]
        session.transcriptionChunks = [TranscriptionChunk(file: path, window: SpeechWindow(start: 0, duration: 1), language: "it-IT", segments: [TranscriptSegment(start: 0.2, duration: 0.2, text: "Primo blocco")])]
        try await workspace.saveSession(session)
        var page = PageSnapshot(); page.anchors = [StrokeAnchor(signature: "ink", audioSessionID: session.id, seconds: 3)]
        _ = try await workspace.addPage(page)
        let audio = AudioController(workspace: workspace); await audio.load()
        audio.startCompression(session.id)
        audio.startTranscription(session); XCTAssertNil(audio.transcribingSessionID)
        await audio.compressionTask?.value; XCTAssertNil(audio.error)
        let compressed = try XCTUnwrap(audio.sessions.first)
        XCTAssertEqual(compressed.segments.first?.codec, "aac"); XCTAssertEqual(compressed.segments.first?.duration, 3.25)
        XCTAssertEqual(compressed.transcriptionChunks?.first?.window, session.transcriptionChunks?.first?.window)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        audio.transcriptionWindowLength = 1
        var windows: [SpeechWindow] = []
        audio.windowRecognition = { url, window, _ in
            XCTAssertEqual(url.pathExtension, "m4a"); windows.append(window)
            let frames = try AudioWindowReader.read(url: url, window: window, chunk: 2048) { XCTAssertLessThanOrEqual($0.frameLength, 2048) }
            XCTAssertGreaterThan(frames, 0)
            return [TranscriptSegment(start: 0, duration: min(0.1, window.duration), text: "Blocco AAC")]
        }
        audio.startTranscription(compressed); await audio.transcriptionTask?.value
        XCTAssertNil(audio.error); XCTAssertEqual(windows.map(\.start), [1, 2, 3]); XCTAssertEqual(windows.last?.duration, 0.25)
        let saved = try await workspace.catalog().sessions.first
        XCTAssertEqual(saved?.transcriptionChunks?.count, 4); XCTAssertEqual(saved?.transcriptionComplete, true)
        let pages = try await workspace.pages(); XCTAssertEqual(pages.first?.anchors.first?.seconds, 3)
        await audio.close()
    }

    private func writePCM(_ url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192))
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        var offset = 0, total = 143325
        while offset < total {
            let count = min(8192, total - offset); buffer.frameLength = AVAudioFrameCount(count)
            for i in 0..<count {
                let t = Double(offset + i) / 44100
                let pulse = (0.25..<0.29).contains(t) || (3.0..<3.04).contains(t)
                samples[i] = pulse ? Float(sin(t * 2 * .pi * 880) * 0.8) : 0
            }
            try file.write(from: buffer); offset += count
        }
    }
    private func onset(_ url: URL, window: SpeechWindow) throws -> Double {
        var count: Int64 = 0, first: Double?
        try AudioWindowReader.read(url: url, window: window, chunk: 2048) { buffer in
            guard let values = buffer.floatChannelData?[0] else { return }
            for i in 0..<Int(buffer.frameLength) where first == nil {
                if abs(values[i]) > 0.12 { first = Double(count + Int64(i)) / buffer.format.sampleRate }
            }
            count += Int64(buffer.frameLength)
        }
        return try XCTUnwrap(first)
    }
}
