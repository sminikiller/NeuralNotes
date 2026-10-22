import UIKit
import NeuralNotesCore

struct LectureNotesFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { "Sbobina interrotta: \(reason)" }
}

@MainActor
extension AudioController {
    func startLectureNotes(_ original: AudioSession, configuration: AIEngineConfiguration, consentKey: String?) {
        guard canTranscribe, transcribingSessionID == nil, notesTask == nil, original.state == "finished",
              original.trashedAt == nil, original.hasTranscriptText else { return }
        notesSessionID = original.id; notesStatusSessionID = original.id; notesProgress = 0
        notesStatus = "Preparazione dei capitoli…"; error = nil
        notesTask = Task { await runLectureNotes(original.id, configuration: configuration, consentKey: consentKey) }
    }

    /// One chapter per request, saved as soon as it is ready: a pause, a lost
    /// connection or a closed notebook never loses the chapters already written.
    private func runLectureNotes(_ id: UUID, configuration: AIEngineConfiguration, consentKey: String?) async {
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idle; notesSessionID = nil; notesTask = nil }
        do {
            guard let session = try await workspace.catalog().sessions.first(where: { $0.id == id }), session.trashedAt == nil else { throw LibraryFailure.missingItem }
            var notes = LectureNotesPlanner.resume(session)
            guard !notes.blocks.isEmpty else { notesStatus = "Nessun testo da rielaborare: trascrivi prima la registrazione."; return }
            notesProgress = Double(notes.completedCount) / Double(notes.blocks.count)
            let generate: @MainActor (AIRequest) async throws -> AIArtifact = notesGeneration ?? { request in
                try await AIEngineRouter.generate(request, configuration: configuration, consentKey: consentKey)
            }
            var failures: [String] = [], consecutive = 0
            for index in notes.blocks.indices where notes.blocks[index].text == nil {
                try Task.checkCancellation()
                let block = notes.blocks[index], at = TranscriptText.clock(block.start)
                notesStatus = "Capitolo \(index + 1)/\(notes.blocks.count) · \(at)" + (failures.isEmpty ? "" : " · \(failures.count) da riprovare")
                guard let request = LectureNotesPlanner.request(for: block, session: session, documentID: workspace.documentID) else {
                    notes.blocks[index].text = ""; continue
                }
                var result: AIArtifact?, failure: Error?
                for attempt in 0..<2 where result == nil {
                    do { result = try await generate(request) }
                    catch is CancellationError { throw CancellationError() }
                    catch { failure = error; if attempt == 0 { try await Task.sleep(for: .seconds(2)) } }
                }
                guard let result else {
                    failures.append(at); consecutive += 1
                    if consecutive >= 3 { throw LectureNotesFailure(reason: "tre capitoli di fila non elaborati. Ultimo errore: \(failure?.localizedDescription ?? "sconosciuto")") }
                    continue
                }
                consecutive = 0
                notes.blocks[index].text = String(LectureNotesPlanner.notesText(from: result).prefix(40_000))
                notes.blocks[index].provider = String(result.provider.prefix(240)); notes.updatedAt = Date()
                try await saveNotes(notes, sessionID: id)
                notesProgress = Double(notes.completedCount) / Double(notes.blocks.count)
            }
            try await saveNotes(notes, sessionID: id)
            notesProgress = Double(notes.completedCount) / Double(notes.blocks.count)
            notesStatus = failures.isEmpty ? "Sbobina completata e salvata."
                : "Sbobina salvata con \(failures.count) capitoli da riprovare (\(failures.prefix(4).joined(separator: ", "))). Premi Riprendi sbobina."
        } catch is CancellationError { notesStatus = "In pausa: i capitoli già pronti sono salvati." }
        catch {
            self.error = error.localizedDescription
            notesStatus = "Interrotta: i capitoli già pronti restano salvati. Premi Riprendi sbobina."
        }
    }

    /// Re-reads the session before saving, so bookmarks or other changes made in
    /// the meantime are kept; a concurrent revision is retried.
    private func saveNotes(_ notes: LectureNotes, sessionID: UUID) async throws {
        for attempt in 0..<3 {
            guard var latest = try await workspace.catalog().sessions.first(where: { $0.id == sessionID }) else { throw LibraryFailure.missingItem }
            guard LectureNotesPlanner.fingerprint(latest) == notes.fingerprint else { throw LectureNotesFailure(reason: "la trascrizione è cambiata durante l’elaborazione") }
            latest.lectureNotes = notes; latest.revision = (latest.revision ?? 0) + 1
            do {
                try await workspace.saveSession(latest)
                if let index = sessions.firstIndex(where: { $0.id == sessionID }) { sessions[index] = latest }
                return
            } catch WorkspaceFailure.staleRevision where attempt < 2 { continue }
        }
    }
}
