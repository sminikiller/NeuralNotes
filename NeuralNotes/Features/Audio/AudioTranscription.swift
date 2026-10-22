import AVFoundation
import UIKit
import NeuralNotesCore

@MainActor
extension AudioController {
    func startTranscription(_ original: AudioSession) {
        guard canTranscribe, transcribingSessionID == nil, original.state == "finished", original.trashedAt == nil else { return }
        transcribingSessionID = original.id; transcriptionStatusSessionID = original.id; error = nil
        transcriptionTask = Task { await runTranscription(original.id) }
    }

    private func runTranscription(_ id: UUID) async {
        // A lecture takes many minutes to process: keep the iPad from locking,
        // which would suspend the job.
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idle; transcribingSessionID = nil; transcriptionTask = nil }
        stopPlayback(); transcriptionProgress = 0
        let log = TranscriptionLog.shared
        do {
            guard var session = try await workspace.catalog().sessions.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
            guard session.trashedAt == nil, session.state == "finished" else { throw WorkspaceFailure.staleRevision }
            if session.transcriptionComplete == true && !session.hasTranscriptText {
                // An empty successful recognition is retryable, never a saved text.
                session.transcriptionChunks = session.transcriptionChunks?.filter { TranscriptText.hasText($0.segments) }
                session.transcriptionComplete = false
            }
            // Older versions stored one entry per word; compact before rewriting the catalog.
            if let chunks = session.transcriptionChunks, TranscriptText.hasText(chunks.flatMap(\.segments)) {
                session.transcriptionChunks = chunks.map { chunk in var value = chunk; value.segments = TranscriptText.phrases(chunk.segments); return value }
                session.transcript = TranscriptText.corrected((session.transcriptionChunks ?? []).flatMap(\.segments),
                    corrections: session.transcriptCorrections ?? [])
            }
            let language = "it-IT", service = AppleTranscriptionService()
            let recognize: @MainActor (URL, SpeechWindow, String) async throws -> (segments: [TranscriptSegment], method: String) = { [weak self] url, window, language in
                if let injected = self?.windowRecognition { return (try await injected(url, window, language), "simulato") }
                let outcome = try await service.recognizeWindow(url: url, window: window, language: language)
                return (outcome.segments, outcome.method.rawValue)
            }
            var plans: [(AudioTimelineSegment, URL, [SpeechWindow])] = []
            var unreadable: [String] = []
            for segment in session.segments {
                let url = try await workspace.url(segment.file)
                do {
                    let measured = try await Self.recordedDuration(url)
                    // Verified AAC may expose a few padding frames. Preserve
                    // the PCM window boundaries so a resumed job reuses chunks.
                    let duration = segment.codec == "aac" && segment.duration > 0 && abs(measured - segment.duration) < 0.05 ? segment.duration : measured
                    plans.append((segment, url, SpeechWindow.plan(duration: duration, maximum: transcriptionWindowLength)))
                } catch {
                    let at = TranscriptText.clock(segment.start)
                    unreadable.append(at)
                    log.add(block: "parte a \(at)", method: "lettura", seconds: 0, characters: 0, error: AppleTranscriptionService.describe(error))
                }
            }
            guard !plans.isEmpty else { throw RecognitionFailure.unreadable("nessuna parte della registrazione è leggibile") }
            let total = max(1, plans.reduce(0) { $0 + $1.2.count })
            var completed = 0, consecutive = 0
            var failures: [String] = [], lastFailure = ""
            for (segment, url, windows) in plans {
                for window in windows {
                    try Task.checkCancellation()
                    if session.transcriptionChunks?.contains(where: { $0.file == segment.file && $0.window == window && $0.language == language }) == true {
                        completed += 1; transcriptionProgress = Double(completed) / Double(total); continue
                    }
                    let at = TranscriptText.clock(segment.start + window.start)
                    let block = "\(completed + 1)/\(total) · \(at)"
                    transcriptionStatus = "Blocco \(block)" + (failures.isEmpty ? "" : " · \(failures.count) da riprovare")
                    let began = Date()
                    var result: (segments: [TranscriptSegment], method: String)?
                    var failure: Error?
                    for attempt in 0..<2 where result == nil {
                        do { result = try await recognize(url, window, language) }
                        catch is CancellationError { throw CancellationError() }
                        catch let error as RecognitionFailure where error.isSystemic { throw error }
                        catch {
                            failure = error
                            if attempt == 0 { transcriptionStatus = "Riprovo il blocco a \(at)…"; try await Task.sleep(for: .milliseconds(500)) }
                        }
                    }
                    guard let result else {
                        // Skip one bad block instead of losing the rest of the lecture.
                        // It has no saved chunk, so Riprendi tries it again.
                        let reason = failure.map(AppleTranscriptionService.describe) ?? "errore sconosciuto"
                        log.add(block: block, method: "—", seconds: Date().timeIntervalSince(began), characters: 0, error: reason)
                        failures.append(at); consecutive += 1; lastFailure = "\(at): \(reason)"
                        if consecutive >= 3 {
                            throw TranscriptionBlockFailure(time: at, reason: "tre blocchi consecutivi non riconosciuti. Ultimo errore: \(reason)")
                        }
                        completed += 1; transcriptionProgress = Double(completed) / Double(total); continue
                    }
                    consecutive = 0
                    var recognized = result.segments
                    for i in recognized.indices { recognized[i].start += segment.start + window.start }
                    recognized = TranscriptText.phrases(recognized)
                    let chunk = TranscriptionChunk(file: segment.file, window: window, language: language, segments: recognized)
                    session.transcriptionChunks = (session.transcriptionChunks ?? []) + [chunk]
                    let raw = (session.transcriptionChunks ?? []).flatMap(\.segments)
                    session.transcript = TranscriptText.corrected(raw, corrections: session.transcriptCorrections ?? [])
                    session.transcriptionComplete = false; session.revision = (session.revision ?? 0) + 1
                    do { try await workspace.saveSession(session) }
                    catch { throw TranscriptionBlockFailure(time: at, reason: "salvataggio non riuscito: \(AppleTranscriptionService.describe(error))") }
                    updateTranscriptionSnapshot(session)
                    log.add(block: block, method: result.method, seconds: Date().timeIntervalSince(began),
                        characters: recognized.reduce(0) { $0 + $1.text.count }, error: nil)
                    completed += 1; transcriptionProgress = Double(completed) / Double(total)
                }
            }
            transcriptionProgress = 1
            let missing = failures.count + unreadable.count
            guard missing == 0 else {
                transcriptionStatus = "Trascrizione conclusa con \(missing) blocchi da riprovare. Premi Riprendi trascrizione: i blocchi salvati non vengono rifatti."
                let places = (unreadable + failures).prefix(6).joined(separator: ", ")
                error = "Blocchi non trascritti a \(places)\(missing > 6 ? "…" : ""). " + (lastFailure.isEmpty ? "Parti audio non leggibili." : "Ultimo errore \(lastFailure)")
                return
            }
            session.transcriptionComplete = true; session.revision = (session.revision ?? 0) + 1
            try await workspace.saveSession(session); updateTranscriptionSnapshot(session)
            transcriptionStatus = session.hasTranscriptText ? "Trascrizione completata e salvata" : "Analisi completata senza testo riconosciuto. Puoi riprovare."
        } catch is CancellationError { transcriptionStatus = "In pausa: puoi riprendere dai blocchi già salvati." }
        catch {
            self.error = AppleTranscriptionService.describe(error)
            transcriptionStatus = "Interrotta: risultati precedenti conservati. Premi Riprendi trascrizione."
        }
    }

    /// Recognizes only the first block and reports method, time and text, so a
    /// failing recording can be diagnosed in seconds instead of a full run.
    func probeFirstWindow(_ session: AudioSession) async {
        guard canTranscribe, transcribingSessionID == nil, let segment = session.segments.first else { return }
        transcribingSessionID = session.id; transcriptionStatusSessionID = session.id; error = nil
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idle; transcribingSessionID = nil }
        stopPlayback(); transcriptionProgress = 0; transcriptionStatus = "Prova del primo blocco…"
        let began = Date(), log = TranscriptionLog.shared
        do {
            let url = try await workspace.url(segment.file)
            let duration = try await Self.recordedDuration(url)
            guard let window = SpeechWindow.plan(duration: duration, maximum: transcriptionWindowLength).first else {
                throw RecognitionFailure.unreadable("nessun audio nel primo blocco")
            }
            let outcome = try await AppleTranscriptionService().recognizeWindow(url: url, window: window, language: "it-IT")
            let text = outcome.segments.map(\.text).joined(separator: " ")
            log.add(block: "prova · 00:00:00", method: outcome.method.rawValue, seconds: Date().timeIntervalSince(began), characters: text.count, error: nil)
            transcriptionStatus = text.isEmpty
                ? "Prova riuscita (\(outcome.method.rawValue)): nessuna voce nei primi \(Int(window.duration)) secondi. La trascrizione completa salterà il silenzio."
                : "Prova riuscita (\(outcome.method.rawValue), \(Int(Date().timeIntervalSince(began))) s): «\(text.prefix(160))»"
        } catch {
            let reason = AppleTranscriptionService.describe(error)
            log.add(block: "prova · 00:00:00", method: "—", seconds: Date().timeIntervalSince(began), characters: 0, error: reason)
            transcriptionStatus = "Prova non riuscita: \(reason)"
        }
        transcriptionProgress = 1
    }

    /// Duration read from the frames; AVURLAsset only as a fallback.
    private static func recordedDuration(_ url: URL) async throws -> Double {
        if let value = try? AudioWindowReader.duration(of: url), value <= 604800 { return value }
        let value = try await AVURLAsset(url: url).load(.duration).seconds
        guard value.isFinite, value > 0, value <= 604800 else { throw RecognitionFailure.unreadable("durata non valida") }
        return value
    }

    private func updateTranscriptionSnapshot(_ session: AudioSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
        if active?.id == session.id { active = session }
    }

    func saveTranscript(_ id: UUID, title: String, blocks: [TranscriptMinute]) async throws {
        guard transcribingSessionID == nil, compressionTask == nil, compressingSessionID == nil, notesSessionID != id else { throw WorkspaceFailure.staleRevision }
        guard var session = try await workspace.catalog().sessions.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        guard session.state == "finished", session.trashedAt == nil, active?.id != id else { throw WorkspaceFailure.staleRevision }
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
