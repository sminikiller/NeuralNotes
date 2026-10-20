import AVFoundation
import NeuralNotesCore

@MainActor
extension AudioController {
    func startTranscription(_ original: AudioSession) {
        guard canTranscribe, transcribingSessionID == nil, original.state == "finished" else { return }
        transcribingSessionID = original.id; error = nil
        transcriptionTask = Task { await runTranscription(original.id) }
    }

    private func runTranscription(_ id: UUID) async {
        defer { transcribingSessionID = nil; transcriptionTask = nil }
        stopPlayback(); transcriptionProgress = 0
        do {
            guard var session = try await workspace.catalog().sessions.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
            if session.transcriptionComplete == true && !session.hasTranscriptText {
                // An empty successful recognition is retryable, never a saved text.
                session.transcriptionChunks = session.transcriptionChunks?.filter { TranscriptText.hasText($0.segments) }
                session.transcriptionComplete = false
            }
            let language = "it-IT", service = AppleTranscriptionService()
            let recognize: @MainActor (URL, SpeechWindow, String) async throws -> [TranscriptSegment] = windowRecognition ?? { url, window, language in
                try await service.transcribeWindow(url: url, window: window, language: language)
            }
            var plans: [(AudioTimelineSegment, URL, [SpeechWindow])] = []
            for segment in session.segments {
                let url = try await workspace.url(segment.file)
                let duration = try await AVURLAsset(url: url).load(.duration).seconds
                guard duration.isFinite, duration > 0, duration <= 604800 else { throw RecognitionFailure.unavailable }
                plans.append((segment, url, SpeechWindow.plan(duration: duration, maximum: 45)))
            }
            guard !plans.isEmpty else { throw RecognitionFailure.unavailable }
            let total = max(1, plans.reduce(0) { $0 + $1.2.count })
            var completed = 0
            for (segment, url, windows) in plans {
                for window in windows {
                    try Task.checkCancellation()
                    if session.transcriptionChunks?.contains(where: { $0.file == segment.file && $0.window == window && $0.language == language }) == true {
                        completed += 1; transcriptionProgress = Double(completed) / Double(total); continue
                    }
                    let at = TranscriptText.clock(segment.start + window.start)
                    transcriptionStatus = "Blocco \(completed + 1)/\(total) · \(at)"
                    var recognized: [TranscriptSegment]
                    do { recognized = try await recognize(url, window, language) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        transcriptionStatus = "Riprovo il blocco a \(at)…"
                        try await Task.sleep(for: .milliseconds(500))
                        do { recognized = try await recognize(url, window, language) }
                        catch is CancellationError { throw CancellationError() }
                        catch { throw TranscriptionBlockFailure(time: at, reason: error.localizedDescription) }
                    }
                    for i in recognized.indices { recognized[i].start += segment.start + window.start }
                    let chunk = TranscriptionChunk(file: segment.file, window: window, language: language, segments: recognized)
                    session.transcriptionChunks = (session.transcriptionChunks ?? []) + [chunk]
                    let raw = (session.transcriptionChunks ?? []).flatMap(\.segments)
                    session.transcript = TranscriptText.corrected(raw, corrections: session.transcriptCorrections ?? [])
                    session.transcriptionComplete = false; session.revision = (session.revision ?? 0) + 1
                    try await workspace.saveSession(session); updateTranscriptionSnapshot(session)
                    completed += 1; transcriptionProgress = Double(completed) / Double(total)
                }
            }
            session.transcriptionComplete = true; session.revision = (session.revision ?? 0) + 1
            try await workspace.saveSession(session); updateTranscriptionSnapshot(session)
            transcriptionProgress = 1
            transcriptionStatus = session.hasTranscriptText ? "Trascrizione completata e salvata" : "Analisi completata senza testo riconosciuto. Puoi riprovare."
        } catch is CancellationError { transcriptionStatus = "In pausa: puoi riprendere dai blocchi già salvati." }
        catch { self.error = error.localizedDescription; transcriptionStatus = "Interrotta: risultati precedenti conservati. Premi Riprendi trascrizione." }
    }

    private func updateTranscriptionSnapshot(_ session: AudioSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
        if active?.id == session.id { active = session }
    }

    func saveTranscript(_ id: UUID, title: String, blocks: [TranscriptMinute]) async throws {
        guard transcribingSessionID == nil else { throw WorkspaceFailure.staleRevision }
        guard var session = try await workspace.catalog().sessions.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        session.title = try LibraryName.validated(title)
        let current = TranscriptText.minutes(session.readableTranscript)
        var corrections = session.transcriptCorrections ?? []
        for block in blocks where current.first(where: { $0.start == block.start })?.text != block.text {
            corrections.removeAll { $0.start == block.start }
            corrections.append(TranscriptCorrection(start: block.start, text: block.text))
        }
        session.transcriptCorrections = corrections
        let chunkText = session.transcriptionChunks?.flatMap(\.segments) ?? []
        let raw = TranscriptText.hasText(chunkText) ? chunkText : session.readableTranscript
        session.transcript = TranscriptText.corrected(raw, corrections: corrections)
        session.revision = (session.revision ?? 0) + 1
        try await workspace.saveSession(session); updateTranscriptionSnapshot(session)
    }
}

private struct TranscriptionBlockFailure: LocalizedError {
    let time: String, reason: String
    var errorDescription: String? { "Trascrizione interrotta a \(time): \(reason). I blocchi precedenti sono salvati." }
}
