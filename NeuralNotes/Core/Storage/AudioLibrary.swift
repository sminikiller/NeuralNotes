import Foundation

public enum AudioLibraryScope: String, CaseIterable, Sendable { case recent, archived, trash }
public enum AudioLibraryAction: Sendable { case rename(String), archive(Bool), trash, restore, clearTranscript }

public enum AudioLibraryQuery {
    public static func sessions(_ sessions: [AudioSession], scope: AudioLibraryScope, query: String = "") -> [AudioSession] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { value in
            let included: Bool
            switch scope {
            case .recent: included = value.trashedAt == nil && value.isArchived != true
            case .archived: included = value.trashedAt == nil && value.isArchived == true
            case .trash: included = value.trashedAt != nil
            }
            return included && (term.isEmpty || value.title.localizedStandardContains(term))
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
}

public extension DocumentWorkspace {
    @discardableResult
    func changeAudioSession(_ id: UUID, expectedRevision: Int, action: AudioLibraryAction, now: Date = Date()) throws -> AudioSession {
        var index = try catalog()
        guard let position = index.sessions.firstIndex(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        var value = index.sessions[position]
        guard value.state == "finished", (value.revision ?? 0) == expectedRevision, expectedRevision < 1_000_000_000,
              now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else { throw WorkspaceFailure.staleRevision }
        switch action {
        case .rename(let title): value.title = try LibraryName.validated(title)
        case .archive(let enabled):
            guard value.trashedAt == nil else { throw WorkspaceFailure.staleRevision }; value.isArchived = enabled
        case .trash: value.trashedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        case .restore: value.trashedAt = nil
        case .clearTranscript:
            value.transcript = []; value.transcriptionChunks = nil; value.transcriptCorrections = nil; value.transcriptionComplete = nil
        }
        value.revision = expectedRevision + 1; index.sessions[position] = value
        // Soft deletion preserves the audio and all stroke/time references.
        // Physical cleanup is a separate operation, never hidden in this action.
        try write(index, "catalog.json"); return value
    }
}
