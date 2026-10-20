import Foundation

public struct AutomaticBackupInfo: Identifiable, Sendable {
    public let url: URL
    public let date: Date
    public let bytes: Int64
    public var id: URL { url }
}

public extension DocumentWorkspace {
    nonisolated var automaticBackupDirectory: URL {
        package.deletingLastPathComponent().appendingPathComponent("AutomaticBackups", isDirectory: true)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
    }
    func automaticBackups() throws -> [AutomaticBackupInfo] {
        let directory = automaticBackupDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: directory.path)) == nil else { throw WorkspaceFailure.invalidPath }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "nnbackup" }
            .map { file in
                let safe = try NativeArchive.fileURL(file.lastPathComponent, in: directory)
                let values = try safe.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return AutomaticBackupInfo(url: safe, date: values.contentModificationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0))
            }.sorted { $0.date > $1.date }
    }
    /// Serialized with all document writes. Rotate only after the new archive commits.
    @discardableResult
    func createAutomaticBackup(metadata: Notebook, minimumInterval: TimeInterval = 600, keep: Int = 5) throws -> URL? {
        guard metadata.documentID == documentID, minimumInterval.isFinite, minimumInterval >= 0, (1...20).contains(keep) else { throw WorkspaceFailure.invalidPath }
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else { return nil }
        let previous = try automaticBackups()
        if let last = previous.first, Date().timeIntervalSince(last.date) < minimumInterval { return nil }
        let directory = automaticBackupDirectory
        let parent = directory.deletingLastPathComponent()
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: parent.path)) == nil else { throw WorkspaceFailure.invalidPath }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("pending-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try NativeArchive.write(package: package, metadata: metadata, to: temporary)
        let destination = directory.appendingPathComponent("backup-\(UUID()).nnbackup")
        try FileManager.default.moveItem(at: temporary, to: destination)
        for old in previous.dropFirst(keep - 1) { try? FileManager.default.removeItem(at: old.url) }
        return destination
    }
}
