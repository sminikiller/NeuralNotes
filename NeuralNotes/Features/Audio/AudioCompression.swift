import AVFoundation
import NeuralNotesCore

enum AudioCompression {
    static func isPCM(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM
    }
    static func encode(source: URL, destination: URL) throws -> AudioCompressionVerification {
        let input = try AVAudioFile(forReading: source), frames = input.length, rate = input.processingFormat.sampleRate
        guard frames > 0, rate.isFinite, (8000...48000).contains(rate), isPCM(source) else { throw Failure.format }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: destination.deletingLastPathComponent().path)
        let required = Double(frames) / rate * 8000 + Double(64 * 1024 * 1024)
        if let available = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue, available < required { throw CocoaError(.fileWriteOutOfSpace) }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw WorkspaceFailure.staleRevision }
        try write(source: source, destination: destination)
        let handle = try FileHandle(forWritingTo: destination); try handle.synchronize(); try handle.close()
        let decoded = try AVAudioFile(forReading: destination)
        guard (decoded.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatMPEG4AAC,
              decoded.processingFormat.channelCount == 1 else { throw Failure.format }
        let bytes = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let check = AudioCompressionVerification(sourceFrames: frames, sourceRate: rate, decodedFrames: decoded.length, decodedRate: decoded.processingFormat.sampleRate, encodedBytes: bytes)
        guard check.isValid else { throw Failure.timing }
        return check
    }
    private static func write(source: URL, destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = input.processingFormat.sampleRate, channels = Int(input.processingFormat.channelCount)
        guard (1...8).contains(channels), let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32768),
              let mixed = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 32768) else { throw Failure.format }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        while input.framePosition < input.length {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(32768, input.length - input.framePosition))
            try input.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData, let target = mixed.floatChannelData?[0] else { throw Failure.format }
            mixed.frameLength = buffer.frameLength
            for frame in 0..<Int(buffer.frameLength) {
                var total: Float = 0
                for channel in 0..<channels { total += samples[channel][frame] }; target[frame] = total / Float(channels)
            }
            try output.write(from: mixed)
        }
        // Scope exit releases the writer and finalizes the M4A before verification.
    }
    enum Failure: LocalizedError {
        case format, timing
        var errorDescription: String? {
            switch self { case .format: return "Formato PCM/AAC non supportato: originale conservato."; case .timing: return "Durata o allineamento oltre tolleranza: originale conservato." }
        }
    }
}

@MainActor
extension AudioController {
    func startCompression(_ id: UUID) {
        guard canTranscribe, compressionTask == nil, transcribingSessionID == nil, playingSessionID == nil else { return }
        compressionTask = Task { await compressSession(id); compressionTask = nil }
    }
    func compressSession(_ id: UUID) async {
        guard !Task.isCancelled, !recording, !transitioning, transcribingSessionID == nil, playingSessionID == nil, compressingSessionID == nil else { return }
        compressingSessionID = id; compressionStatus = "Preparazione AAC…"; defer { compressingSessionID = nil }
        do {
            let plan: AudioCompressionPlan
            if let pending = try await workspace.pendingAudioCompression() { guard pending.sessionID == id else { throw WorkspaceFailure.staleRevision }; plan = pending }
            else {
                guard let session = try await workspace.catalog().sessions.first(where: { $0.id == id }), session.state == "finished" else { return }
                let candidates = Array(Set(session.segments.map(\.file)))
                var sources: [String] = []
                for path in candidates {
                    let url = try await workspace.url(path)
                    if await Task.detached(priority: .utility, operation: { AudioCompression.isPCM(url) }).value { sources.append(path) }
                }
                guard !sources.isEmpty else { return }
                plan = try await workspace.beginAudioCompression(id, sources: sources.sorted())
            }
            if !plan.committed {
                for (index, part) in plan.parts.enumerated() where part.verification == nil {
                    try Task.checkCancellation(); compressionStatus = "AAC · parte \(index + 1)/\(plan.parts.count)"
                    let source = try await workspace.url(part.source), destination = try await workspace.url(part.destination)
                    // Only this journal's unique, unverified output can be replaced.
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    let job = Task.detached(priority: .utility) { try AudioCompression.encode(source: source, destination: destination) }
                    let result = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                    _ = try await workspace.verifyAudioCompressionPart(plan.id, destination: part.destination, verification: result)
                }
            }
            try Task.checkCancellation()
            let removed = try await workspace.commitAudioCompression(plan.id)
            sessions = try await workspace.catalog().sessions
            compressionStatus = "Compressione completata · PCM rimossi: \(ByteCountFormatter.string(fromByteCount: removed, countStyle: .file))"
        } catch is CancellationError { compressionStatus = "Compressione in pausa: riprenderà all’apertura del quaderno." }
        catch { self.error = "Compressione interrotta: \(error.localizedDescription)"; compressionStatus = "Originali o copie AAC verificate conservati. Puoi riprendere la conversione." }
    }
}
