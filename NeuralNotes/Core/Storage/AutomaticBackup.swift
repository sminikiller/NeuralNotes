import Foundation

public struct AutomaticBackupInfo: Identifiable, Sendable {
    public let url: URL
    public let date: Date
    public let bytes: Int64
    public var id: URL { url }
}

public enum AutomaticBackupPolicy {
    public static func budget(copyBytes: Int64) -> Int64 {
        let size = max(0, copyBytes)
        return min(1 << 30, max(64 << 20, size >= (1 << 30) / 3 ? 1 << 30 : size * 3))
    }
    /// Input sizes are newest first. The two newest versions are protected even
    /// when they exceed the budget; remove only the oldest unprotected versions.
    public static func retainedCount(sizes: [Int64], maximumBytes: Int64, keep: Int = 5) -> Int {
        var count = min(sizes.count, max(2, min(20, keep)))
        while count > 2 {
            var total: Int64 = 0
            for size in sizes.prefix(count) {
                let value = max(0, size)
                total = value > Int64.max - total ? Int64.max : total + value
            }
            if total <= max(0, maximumBytes) { break }
            count -= 1
        }
        return count
    }
}

public struct AutomaticBackupUsage: Sendable {
    public let usedBytes: Int64
    public let budgetBytes: Int64
    public let copies: Int
    public var exceedsBudget: Bool { usedBytes > budgetBytes }
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
                let name = safe.deletingPathExtension().lastPathComponent.dropFirst("backup-".count)
                let stamp = name.prefix(while: { $0.isNumber })
                let dated = stamp.count == 20 ? UInt64(stamp).map { Date(timeIntervalSince1970: Double($0) / 1_000_000) } : nil
                return AutomaticBackupInfo(url: safe, date: dated ?? values.contentModificationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0))
            }.sorted { $0.date == $1.date ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.date > $1.date }
    }
    func automaticBackupUsage() throws -> AutomaticBackupUsage {
        let used = try automaticBackups().reduce(Int64(0)) { sum, value in value.bytes > Int64.max - sum ? Int64.max : sum + value.bytes }
        let notebook = try PackageFiles.list(in: package).reduce(Int64(0)) { sum, file in
            let size = Int64(try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            return size > Int64.max - sum ? Int64.max : sum + size
        }
        return AutomaticBackupUsage(usedBytes: used, budgetBytes: AutomaticBackupPolicy.budget(copyBytes: notebook), copies: try automaticBackups().count)
    }
    /// Serialized with all document writes. Rotate only after the new archive commits.
    @discardableResult
    func createAutomaticBackup(metadata: Notebook, minimumInterval: TimeInterval = 600, keep: Int = 5, maximumBytes: Int64? = nil) throws -> URL? {
        try Task.checkCancellation()
        guard metadata.documentID == documentID, minimumInterval.isFinite, minimumInterval >= 0, (1...20).contains(keep) else { throw WorkspaceFailure.invalidPath }
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else { return nil }
        guard try pendingAudioCompression() == nil else { return nil }
        let previous = try automaticBackups()
        if let last = previous.first, Date().timeIntervalSince(last.date) < minimumInterval { return nil }
        let directory = automaticBackupDirectory
        let parent = directory.deletingLastPathComponent()
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: parent.path)) == nil else { throw WorkspaceFailure.invalidPath }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("pending-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try NativeArchive.write(package: package, metadata: metadata, to: temporary)
        // Do not publish or rotate copies if cancellation arrived during the last
        // write/synchronize step, after the archive's last streaming checkpoint.
        try Task.checkCancellation()
        // File providers may round mtimes. Persist a monotonic order in the
        // filename, rather than ordering new copies by a random UUID on ties.
        let now = max(0, Date().timeIntervalSince1970 * 1_000_000)
        let last = max(0, (previous.first?.date.timeIntervalSince1970 ?? 0) * 1_000_000)
        let stamp = UInt64(min(Double(UInt64.max / 2), max(now, last + 2)))
        let name = String(format: "backup-%020llu-", stamp) + "\(UUID()).nnbackup"
        let destination = try NativeArchive.fileURL(name, in: directory)
        try FileManager.default.moveItem(at: temporary, to: destination)
        let size = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let budget: Int64
        if let maximumBytes { budget = max(0, maximumBytes) } else { budget = try automaticBackupUsage().budgetBytes }
        let count = AutomaticBackupPolicy.retainedCount(sizes: [size] + previous.map(\.bytes), maximumBytes: budget, keep: keep)
        for old in previous.dropFirst(max(0, count - 1)) { try FileManager.default.removeItem(at: old.url) }
        return destination
    }
}
