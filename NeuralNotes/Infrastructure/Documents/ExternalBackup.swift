import Foundation
import NeuralNotesCore

enum ExternalBackupDestination {
    static var name: String? { UserDefaults.standard.string(forKey: "backup.external.name") }
    static var bookmark: Data? { UserDefaults.standard.data(forKey: "backup.external.bookmark") }
    static func choose(_ folder: URL) throws {
        let scoped = folder.startAccessingSecurityScopedResource(); defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let data = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: "backup.external.bookmark")
        UserDefaults.standard.set(folder.lastPathComponent, forKey: "backup.external.name")
    }
    static func remove() {
        UserDefaults.standard.removeObject(forKey: "backup.external.bookmark")
        UserDefaults.standard.removeObject(forKey: "backup.external.name")
    }
}

actor ExternalBackupWriter {
    static let shared = ExternalBackupWriter()
    /// Called after the local archive has committed. A failure never rotates or
    /// removes the local backup; only this app's UUID directory is managed.
    func copy(_ backup: URL, documentID: UUID, force: Bool = false) throws -> URL? {
        guard let bookmark = ExternalBackupDestination.bookmark else { return nil }
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scoped = folder.startAccessingSecurityScopedResource(); defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if stale { try ExternalBackupDestination.choose(folder) }
        let directory = folder.appendingPathComponent("NeuralNotesBackups", isDirectory: true).appendingPathComponent(documentID.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(backup.lastPathComponent)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil else { throw CocoaError(.fileWriteInvalidFileName) }
        if !force && FileManager.default.fileExists(atPath: destination.path) { return destination }
        var coordinationError: NSError?, result: Result<URL, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result { try Self.write(backup, documentID: documentID, folder: coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }; return try result.get()
    }
    /// Separated from security-scoped access so rotation can be tested with a
    /// temporary directory on the Apple runner.
    static func write(_ backup: URL, documentID: UUID, folder: URL) throws -> URL {
        guard backup.pathExtension == "nnbackup", backup.lastPathComponent.hasPrefix("backup-"),
              try backup.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
        let parent = folder.appendingPathComponent("NeuralNotesBackups", isDirectory: true)
        let directory = parent.appendingPathComponent(documentID.uuidString, isDirectory: true)
        for url in [parent, directory] where (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("pending-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: backup, to: temporary)
        let destination = directory.appendingPathComponent(backup.lastPathComponent)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil else { throw CocoaError(.fileWriteInvalidFileName) }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try FileManager.default.moveItem(at: temporary, to: destination)
        let versions = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "nnbackup" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
        // Keep the new version even when a provider preserves its source mtime.
        let ordered = [destination] + versions.filter { $0 != destination }
        let sizes = try ordered.map { Int64(try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let count = AutomaticBackupPolicy.retainedCount(sizes: sizes, maximumBytes: AutomaticBackupPolicy.budget(copyBytes: sizes[0]))
        for old in ordered.dropFirst(count) {
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: old.path)) == nil else { continue }
            try FileManager.default.removeItem(at: old)
        }
        return destination
    }
}
