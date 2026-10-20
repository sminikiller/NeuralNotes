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
    case permission, unavailable, missingCapability, timeout
    var errorDescription: String? {
        switch self {
        case .permission: return "Riconoscimento vocale non autorizzato. Controlla le impostazioni dell’iPad."
        case .unavailable: return "Trascrizione locale non disponibile per questa lingua o su questo dispositivo. Nessun audio è stato inviato online."
        case .missingCapability: return "Aggiungi Riconoscimento vocale nelle impostazioni delle funzionalità del progetto Swift Playground, poi esegui nuovamente l’app."
        case .timeout: return "Il riconoscimento non ha concluso questo blocco entro 90 secondi. Puoi riprendere dai blocchi salvati."
        }
    }
}

@MainActor
final class AppleTranscriptionService: TranscriptionService {
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[TranscriptSegment], Error>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func transcribe(url: URL, language: String = "it-IT") async throws -> [TranscriptSegment] {
        let asset = AVURLAsset(url: url)
        let duration: Double = try await asset.load(.duration).seconds
        var results: [TranscriptSegment] = []
        for window in SpeechWindow.plan(duration: duration, maximum: 45) {
            var segments = try await transcribeWindow(url: url, window: window, language: language)
            for index in segments.indices { segments[index].start += window.start }
            results.append(contentsOf: segments)
        }
        return results
    }

    func transcribeWindow(url: URL, window: SpeechWindow, language: String) async throws -> [TranscriptSegment] {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let duration: Double = try await asset.load(.duration).seconds
        guard window.start >= 0, window.duration > 0, duration.isFinite else { throw RecognitionFailure.unavailable }
        if window.start == 0 && window.duration >= duration { return try await recognize(url: url, language: language) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecognitionFailure.unavailable
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
        return try await recognize(url: part, language: language)
    }

    private func recognize(url: URL, language: String) async throws -> [TranscriptSegment] {
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecognitionFailure.missingCapability
        }
        let permitted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        guard permitted else { throw RecognitionFailure.permission }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw RecognitionFailure.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
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
                    Task { @MainActor in
                        guard self?.generation == identifier else { return }
                        if let error { self?.complete(.failure(error)) }
                        else if final { self?.complete(.success(segments)) }
                    }
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    guard self?.generation == identifier else { return }
                    self?.task?.cancel(); self?.complete(.failure(RecognitionFailure.timeout))
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
            guard exporter.status == .completed else { throw exporter.error ?? RecognitionFailure.unavailable }
        } onCancel: {
            Task { @MainActor [self] in exporter.cancelExport() }
        }
    }
}
#endif
