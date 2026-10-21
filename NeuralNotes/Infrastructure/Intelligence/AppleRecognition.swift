import Foundation
import Vision
import Speech
import AVFoundation
import NeuralNotesCore

struct VisionOCRService: OCRService {
    func recognize(image: Data) async throws -> [OCRTextRegion] {
        let operation: Task<[OCRTextRegion], Error> = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: image, options: [:]).perform([request])
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { observation -> OCRTextRegion? in
                guard let text = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return OCRTextRegion(text: text.string, confidence: text.confidence,
                    x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
        }
        return try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }
}

enum RecognitionFailure: LocalizedError {
    case permission, unavailable, missingCapability, timeout(Double), unreadable(String)
    var errorDescription: String? {
        switch self {
        case .permission: return "Riconoscimento vocale non autorizzato. Controlla le impostazioni dell’iPad."
        case .unavailable: return "Trascrizione italiana sul dispositivo non disponibile. In Impostazioni › Generali › Tastiera attiva Dettatura con l’italiano e attendi il download, poi riprova. Nessun audio è stato inviato online."
        case .missingCapability: return "Aggiungi Riconoscimento vocale nelle impostazioni delle funzionalità del progetto Swift Playground, poi esegui nuovamente l’app."
        case .timeout(let seconds): return "Il riconoscimento non ha concluso il blocco entro \(Int(seconds)) secondi."
        case .unreadable(let detail): return "Audio non leggibile: \(detail)"
        }
    }
    /// Problems that would fail every block: stop instead of skipping one block.
    var isSystemic: Bool {
        switch self { case .permission, .unavailable, .missingCapability: return true; case .timeout, .unreadable: return false }
    }
}

/// Reads a recorded window straight from its file into PCM buffers. No export
/// session or temporary file is involved, so any recording length works.
enum AudioWindowReader {
    /// Frames divided by sample rate. AVURLAsset estimates can be wrong for a
    /// long CAF or one that was not closed properly.
    static func duration(of url: URL) throws -> Double {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw RecognitionFailure.unreadable(AppleTranscriptionService.describe(error)) }
        let rate = file.processingFormat.sampleRate
        guard rate.isFinite, rate > 0, file.length > 0 else { throw RecognitionFailure.unreadable("durata non valida") }
        return Double(file.length) / rate
    }

    /// Delivers the window in bounded buffers and returns the frames delivered.
    @discardableResult
    static func read(url: URL, window: SpeechWindow, chunk: AVAudioFrameCount = 16_384, deliver: (AVAudioPCMBuffer) -> Void) throws -> Int64 {
        guard chunk > 0, chunk <= 65_536 else { throw RecognitionFailure.unreadable("dimensione del buffer non valida") }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let range = window.frames(sampleRate: format.sampleRate, length: file.length) else { return 0 }
        file.framePosition = range.lowerBound
        let total = range.upperBound - range.lowerBound
        var delivered: Int64 = 0
        while delivered < total {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(Int64(chunk), total - delivered))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw RecognitionFailure.unreadable("memoria insufficiente per il blocco")
            }
            try file.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0 else { throw RecognitionFailure.unreadable("il blocco termina prima dei frame attesi") }
            deliver(buffer); delivered += Int64(buffer.frameLength)
        }
        return delivered
    }
}

/// One recognizer for a whole transcription. Each window is read directly from
/// the recording; the previous m4a export remains as an independent fallback.
@MainActor
final class AppleTranscriptionService: TranscriptionService {
    enum Method: String { case buffer = "lettura diretta", export = "conversione m4a" }
    struct Outcome { let segments: [TranscriptSegment]; let method: Method }
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[TranscriptSegment], Error>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var recognizers: [String: SFSpeechRecognizer] = [:]
    private var authorized = false
    private var finishedWindows = 0

    func transcribe(url: URL, language: String = "it-IT") async throws -> [TranscriptSegment] {
        var results: [TranscriptSegment] = []
        let duration = try AudioWindowReader.duration(of: url)
        for window in SpeechWindow.plan(duration: duration, maximum: 45) {
            var segments = try await transcribeWindow(url: url, window: window, language: language)
            for index in segments.indices { segments[index].start += window.start }
            results.append(contentsOf: segments)
        }
        return results
    }

    func transcribeWindow(url: URL, window: SpeechWindow, language: String) async throws -> [TranscriptSegment] {
        try await recognizeWindow(url: url, window: window, language: language).segments
    }

    func recognizeWindow(url: URL, window: SpeechWindow, language: String) async throws -> Outcome {
        try Task.checkCancellation()
        let recognizer = try await prepare(language)
        // The first block may have to load the Italian model.
        let limit = finishedWindows == 0 ? 180 : max(60, window.duration * 3)
        do {
            let request = SFSpeechAudioBufferRecognitionRequest(); configure(request)
            let segments = try await run(request, recognizer: recognizer, limit: limit) {
                let frames = try AudioWindowReader.read(url: url, window: window) { request.append($0) }
                request.endAudio()
                if frames == 0 { throw RecognitionFailure.unreadable("nessun frame nel blocco") }
            }
            finishedWindows += 1
            return Outcome(segments: segments, method: .buffer)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as RecognitionFailure where failure.isSystemic { throw failure }
        catch let direct {
            do {
                let segments = try await exportedWindow(url: url, window: window, recognizer: recognizer, limit: limit)
                finishedWindows += 1
                return Outcome(segments: segments, method: .export)
            } catch is CancellationError { throw CancellationError() }
            catch { throw WindowFailure(direct: direct, export: error) }
        }
    }

    private func exportedWindow(url: URL, window: SpeechWindow, recognizer: SFSpeechRecognizer, limit: Double) async throws -> [TranscriptSegment] {
        let asset = AVURLAsset(url: url)
        let duration: Double = try await asset.load(.duration).seconds
        guard window.start >= 0, window.duration > 0, duration.isFinite else { throw RecognitionFailure.unreadable("durata non valida") }
        if window.start == 0 && window.duration >= duration {
            let request = SFSpeechURLRecognitionRequest(url: url); configure(request)
            return try await run(request, recognizer: recognizer, limit: limit) { }
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecognitionFailure.unreadable("conversione non disponibile")
        }
        let part = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: part) }
        let start = CMTime(seconds: window.start, preferredTimescale: 44100)
        let length = CMTime(seconds: min(window.duration, duration - window.start), preferredTimescale: 44100)
        exporter.timeRange = CMTimeRange(start: start, duration: length)
        #if compiler(>=6.2)
        try await exporter.export(to: part, as: .m4a)
        #else
        exporter.outputURL = part; exporter.outputFileType = .m4a
        try await LegacySpeechAudioExport(exporter: exporter).run()
        #endif
        try Task.checkCancellation()
        let request = SFSpeechURLRecognitionRequest(url: part); configure(request)
        return try await run(request, recognizer: recognizer, limit: limit) { }
    }

    private func configure(_ request: SFSpeechRecognitionRequest) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
    }

    private func prepare(_ language: String) async throws -> SFSpeechRecognizer {
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecognitionFailure.missingCapability
        }
        if !authorized {
            let permitted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
            }
            guard permitted else { throw RecognitionFailure.permission }
            authorized = true
        }
        if let cached = recognizers[language], cached.isAvailable { return cached }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw RecognitionFailure.unavailable }
        recognizers[language] = recognizer
        return recognizer
    }

    /// `feed` runs after the task starts, so buffered audio reaches a live request.
    private func run(_ request: SFSpeechRecognitionRequest, recognizer: SFSpeechRecognizer, limit: Double,
                     feed: () throws -> Void) async throws -> [TranscriptSegment] {
        try Task.checkCancellation()
        let identifier = UUID(); generation = identifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let final = result?.isFinal ?? false
                    let segments = result?.bestTranscription.segments.map {
                        TranscriptSegment(start: $0.timestamp, duration: $0.duration, text: $0.substring)
                    } ?? []
                    // Silence (common in the first minute of a lecture) arrives as an
                    // error. It is an empty block, never a reason to stop the job.
                    let silent = error.map(Self.isNoSpeech) ?? false
                    let failure = error.map { Self.describe($0) }
                    Task { @MainActor in
                        guard self?.generation == identifier else { return }
                        if let failure {
                            if silent || !segments.isEmpty { self?.complete(.success(segments)) }
                            else { self?.complete(.failure(RecognizerError(detail: failure))) }
                        } else if final { self?.complete(.success(segments)) }
                    }
                }
                do { try feed() } catch {
                    task?.cancel(); complete(.failure(error)); return
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(limit)) } catch { return }
                    guard self?.generation == identifier else { return }
                    self?.task?.cancel(); self?.complete(.failure(RecognitionFailure.timeout(limit)))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.generation == identifier else { return }
                self?.task?.cancel(); self?.complete(.failure(CancellationError()))
            }
        }
    }

    private func complete(_ result: Result<[TranscriptSegment], Error>) {
        guard let continuation else { return }
        self.continuation = nil; task = nil; generation = UUID()
        timeout?.cancel(); timeout = nil
        continuation.resume(with: result)
    }

    nonisolated static func isNoSpeech(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == "kAFAssistantErrorDomain" && value.code == 1110 { return true }
        let text = value.localizedDescription.lowercased()
        return text.contains("no speech") || text.contains("nessun parlato") || text.contains("nessuna voce")
    }

    /// Step-independent description with domain and code, for the panel and the log.
    nonisolated static func describe(_ error: Error) -> String {
        if let known = error as? LocalizedError, let text = known.errorDescription { return text }
        let value = error as NSError
        return "\(value.localizedDescription) (\(value.domain) \(value.code))"
    }
}

private struct RecognizerError: LocalizedError {
    let detail: String
    var errorDescription: String? { "riconoscimento: \(detail)" }
}

private struct WindowFailure: LocalizedError {
    let direct: Error, export: Error
    var errorDescription: String? {
        "lettura diretta → \(AppleTranscriptionService.describe(direct)); conversione m4a → \(AppleTranscriptionService.describe(export))"
    }
}

#if compiler(<6.2)
/// Older SDKs expose a callback API. Keep the non-Sendable session on MainActor;
/// cancellation captures this actor-isolated owner rather than the AVFoundation object.
@MainActor
private final class LegacySpeechAudioExport {
    private let exporter: AVAssetExportSession

    init(exporter: AVAssetExportSession) { self.exporter = exporter }

    func run() async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !Task.isCancelled else { continuation.resume(); return }
                exporter.exportAsynchronously { continuation.resume() }
            }
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw exporter.error ?? RecognitionFailure.unreadable("conversione non completata") }
        } onCancel: {
            Task { @MainActor [self] in exporter.cancelExport() }
        }
    }
}
#endif
