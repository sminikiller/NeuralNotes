import Foundation

public struct AudioCompressionVerification: Codable, Sendable {
    public let sourceFrames: Int64, decodedFrames: Int64
    public let sourceRate: Double, decodedRate: Double
    public let encodedBytes: Int64
    public init(sourceFrames: Int64, sourceRate: Double, decodedFrames: Int64, decodedRate: Double, encodedBytes: Int64) {
        self.sourceFrames = sourceFrames; self.sourceRate = sourceRate; self.decodedFrames = decodedFrames; self.decodedRate = decodedRate; self.encodedBytes = encodedBytes
    }
    public var duration: Double { Double(sourceFrames) / sourceRate }
    public var isValid: Bool {
        guard sourceFrames > 0, decodedFrames > 0, encodedBytes > 0,
              sourceRate.isFinite, decodedRate.isFinite, (8000...192000).contains(sourceRate), (8000...192000).contains(decodedRate), duration <= 604800 else { return false }
        // No time scaling is applied to anchors or transcription windows. Require
        // endpoint drift below 50 ms as well as the 0.5 s duration bound.
        let drift = abs(duration - Double(decodedFrames) / decodedRate)
        return drift <= 0.5 && drift < 0.05
    }
}
public struct AudioCompressionPart: Codable, Sendable {
    public let source: String, destination: String
    public let sourceBytes: Int64, modified: Double
    public var verification: AudioCompressionVerification?
}
public struct AudioCompressionPlan: Codable, Sendable {
    public static let path = "recovery/audio-compression.json"
    public let id: UUID, documentID: UUID, sessionID: UUID
    public let segments: [AudioTimelineSegment]
    public var parts: [AudioCompressionPart]
    public var committed = false
}

public extension DocumentWorkspace {
    func pendingAudioCompression() throws -> AudioCompressionPlan? {
        let file = try url(AudioCompressionPlan.path)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2 * 1024 * 1024 else { throw LibraryFailure.corruptDocument }
        let plan = try JSONDecoder().decode(AudioCompressionPlan.self, from: Data(contentsOf: file))
        guard plan.documentID == documentID, !plan.parts.isEmpty, plan.parts.count <= 1000,
              !plan.segments.isEmpty, plan.segments.count <= 1000,
              Set(plan.parts.map(\.source)).isSubset(of: Set(plan.segments.map(\.file))),
              Set(plan.parts.map(\.source)).isDisjoint(with: Set(plan.parts.map(\.destination))),
              Set(plan.parts.map(\.source)).count == plan.parts.count, Set(plan.parts.map(\.destination)).count == plan.parts.count else { throw LibraryFailure.corruptDocument }
        for part in plan.parts {
            guard part.source.hasPrefix("audio/"), part.destination.hasPrefix("audio/compressed-\(plan.id)-"),
                  part.destination.hasSuffix(".m4a"), part.source != part.destination, part.sourceBytes > 0,
                  part.modified.isFinite, part.verification?.isValid != false else { throw LibraryFailure.corruptDocument }
            _ = try url(part.source); _ = try url(part.destination)
        }
        return plan
    }
    func beginAudioCompression(_ id: UUID, sources: [String]) throws -> AudioCompressionPlan {
        if let pending = try pendingAudioCompression() {
            guard pending.sessionID == id else { throw LibraryFailure.recoveryRequired("Riprendi prima la compressione interrotta.") }; return pending
        }
        let index = try catalog()
        guard let session = index.sessions.first(where: { $0.id == id }), session.state == "finished", session.trashedAt == nil,
              index.sessions.allSatisfy({ $0.state != "recording" }), !sources.isEmpty, sources.count <= 1000,
              Set(sources).count == sources.count, Set(sources).isSubset(of: Set(session.segments.map(\.file))) else { throw WorkspaceFailure.staleRevision }
        let identifier = UUID()
        var parts: [AudioCompressionPart] = []
        for source in sources {
            guard source.hasPrefix("audio/") else { throw WorkspaceFailure.invalidPath }
            let info = try url(source).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard info.isRegularFile == true, let size = info.fileSize, size > 0, let modified = info.contentModificationDate else { throw LibraryFailure.corruptDocument }
            let destination = "audio/compressed-\(identifier)-\(UUID()).m4a"
            guard !FileManager.default.fileExists(atPath: try url(destination).path) else { throw WorkspaceFailure.staleRevision }
            parts.append(AudioCompressionPart(source: source, destination: destination, sourceBytes: Int64(size), modified: modified.timeIntervalSince1970))
        }
        let plan = AudioCompressionPlan(id: identifier, documentID: documentID, sessionID: id, segments: session.segments, parts: parts)
        try saveCompressionPlan(plan); return plan
    }
    /// Abort only before references have switched. A committed conversion must
    /// finish cleanup; its AAC files can already be the authoritative originals.
    func discardAudioCompression(_ id: UUID) throws {
        guard let plan = try pendingAudioCompression(), plan.id == id, !plan.committed else { throw WorkspaceFailure.staleRevision }
        let current = try catalog()
        guard current.sessions.first(where: { $0.id == plan.sessionID })?.segments == plan.segments else { throw WorkspaceFailure.staleRevision }
        var protected = Set(CatalogRecovery.references(current))
        let previous = try url(CatalogRecovery.previousPath)
        if FileManager.default.fileExists(atPath: previous.path) { protected.formUnion(CatalogRecovery.references(try CatalogRecovery.read(CatalogRecovery.previousPath, package: package))) }
        protected.formUnion(try CatalogRecovery.retainedMedia(in: package))
        guard Set(plan.parts.map(\.destination)).isDisjoint(with: protected) else { throw WorkspaceFailure.staleRevision }
        for part in plan.parts { try checkCompressionSource(part) }
        for part in plan.parts {
            let file = try url(part.destination)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        try FileManager.default.removeItem(at: url(AudioCompressionPlan.path))
    }
    func verifyAudioCompressionPart(_ id: UUID, destination: String, verification: AudioCompressionVerification) throws -> AudioCompressionPlan {
        guard var plan = try pendingAudioCompression(), plan.id == id, !plan.committed,
              let offset = plan.parts.firstIndex(where: { $0.destination == destination }), verification.isValid else { throw LibraryFailure.corruptDocument }
        let part = plan.parts[offset]; try checkCompressionSource(part)
        guard plan.segments.filter({ $0.file == part.source }).allSatisfy({
            $0.start.isFinite && $0.duration.isFinite && $0.start >= 0 && $0.duration > 0 &&
            abs($0.duration - verification.duration) < 0.05 && abs($0.duration - Double(verification.decodedFrames) / verification.decodedRate) < 0.05
        }) else { throw LibraryFailure.recoveryRequired("La durata nel catalogo non coincide con l’audio originale: PCM conservato.") }
        let size = try url(destination).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, Int64(size.fileSize ?? 0) == verification.encodedBytes else { throw LibraryFailure.corruptDocument }
        plan.parts[offset].verification = verification; try saveCompressionPlan(plan); return plan
    }
    /// Atomic reference switch, followed by retryable cleanup. A crash at any
    /// point keeps either the PCM references or all verified AAC references.
    @discardableResult
    func commitAudioCompression(_ id: UUID) throws -> Int64 {
        guard var plan = try pendingAudioCompression(), plan.id == id, plan.parts.allSatisfy({ $0.verification?.isValid == true }) else { throw LibraryFailure.corruptDocument }
        var current = try catalog()
        guard let session = current.sessions.first(where: { $0.id == plan.sessionID }), session.state == "finished" else { throw WorkspaceFailure.staleRevision }
        let mapping = Dictionary(uniqueKeysWithValues: plan.parts.map { ($0.source, $0) })
        let mappedSegments = plan.segments.map { compressedSegment($0, mapping: mapping) }
        let switched = session.segments == mappedSegments
        guard switched || (!plan.committed && session.segments == plan.segments) else { throw WorkspaceFailure.staleRevision }
        for part in plan.parts {
            let info = try url(part.destination).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard info.isRegularFile == true, Int64(info.fileSize ?? 0) == part.verification?.encodedBytes else { throw LibraryFailure.corruptDocument }
            if !switched { try checkCompressionSource(part) }
        }
        if !switched {
            current = try compressedCatalog(current, mapping: mapping, requireFinished: true)
            try write(current, "catalog.json")
        }
        plan.committed = true; try saveCompressionPlan(plan)
        let previousFile = try url(CatalogRecovery.previousPath)
        if FileManager.default.fileExists(atPath: previousFile.path) {
            let previous = try CatalogRecovery.read(CatalogRecovery.previousPath, package: package)
            try write(compressedCatalog(previous, mapping: mapping), CatalogRecovery.previousPath)
        }
        // Explicit recovery snapshots can retain an original PCM. Never free
        // their bytes silently; the UI reports only bytes actually removed.
        var protected = Set(CatalogRecovery.references(try catalog()))
        if FileManager.default.fileExists(atPath: previousFile.path) { protected.formUnion(CatalogRecovery.references(try CatalogRecovery.read(CatalogRecovery.previousPath, package: package))) }
        protected.formUnion(try CatalogRecovery.retainedMedia(in: package))
        var removed: Int64 = 0
        for part in plan.parts where !protected.contains(part.source) {
            let source = try url(part.source)
            if FileManager.default.fileExists(atPath: source.path) {
                try checkCompressionSource(part); try FileManager.default.removeItem(at: source); removed += part.sourceBytes
            }
        }
        try FileManager.default.removeItem(at: url(AudioCompressionPlan.path))
        return removed
    }
    private func checkCompressionSource(_ part: AudioCompressionPart) throws {
        let info = try url(part.source).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        guard info.isRegularFile == true, Int64(info.fileSize ?? 0) == part.sourceBytes,
              abs((info.contentModificationDate?.timeIntervalSince1970 ?? -.infinity) - part.modified) < 0.001 else { throw WorkspaceFailure.staleRevision }
    }
    private func saveCompressionPlan(_ plan: AudioCompressionPlan) throws {
        let file = try url(AudioCompressionPlan.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(plan).write(to: file, options: .atomic)
    }
    private func compressedSegment(_ source: AudioTimelineSegment, mapping: [String: AudioCompressionPart]) -> AudioTimelineSegment {
        guard let part = mapping[source.file] else { return source }
        var value = source; value.file = part.destination; value.codec = "aac"; value.bitRate = 64_000; value.originalBytes = part.sourceBytes; return value
    }
    private func compressedCatalog(_ input: DocumentCatalog, mapping: [String: AudioCompressionPart], requireFinished: Bool = false) throws -> DocumentCatalog {
        var value = input
        for i in value.sessions.indices {
            guard value.sessions[i].segments.contains(where: { mapping[$0.file] != nil }) else { continue }
            guard (!requireFinished || value.sessions[i].state == "finished"), (value.sessions[i].revision ?? 0) < 1_000_000_000 else { throw WorkspaceFailure.staleRevision }
            value.sessions[i].segments = value.sessions[i].segments.map { compressedSegment($0, mapping: mapping) }
            if var chunks = value.sessions[i].transcriptionChunks {
                for j in chunks.indices { if let part = mapping[chunks[j].file] { chunks[j].file = part.destination } }; value.sessions[i].transcriptionChunks = chunks
            }
            value.sessions[i].revision = (value.sessions[i].revision ?? 0) + 1
        }; return value
    }
}
