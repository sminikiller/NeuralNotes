import Foundation
import CryptoKit

public enum SnapshotDigest {
    public static func package(_ package: URL, metadata: Notebook) throws -> String {
        var hash = SHA256()
        hash.update(data: Data("\(metadata.title)|\(metadata.cover.rawValue)|\(metadata.isFavorite)".utf8))
        for file in try PackageFiles.list(in: package).sorted(by: { $0.path < $1.path }) where file.path != "metadata.json" {
            let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            hash.update(data: Data("\n\(file.path.utf8.count):\(file.path):\(size)\n".utf8))
            let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
            while let bytes = try handle.read(upToCount: 256 * 1024), !bytes.isEmpty { try Task.checkCancellation(); hash.update(data: bytes) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
public extension DocumentWorkspace {
    func cloudSnapshot(metadata: Notebook) throws -> (archive: URL, digest: String) {
        let archive = try exportNative(metadata: metadata)
        do { return (archive, try cloudDigest(metadata: metadata)) }
        catch { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()); throw error }
    }
    /// Caller holds the process-wide cloud lease. Never replace a concurrently edited revision.
    func installCloudSnapshot(_ incoming: URL, metadata: Notebook, expectedLocal: String) throws {
        let inspected = try NativePackageInspector.inspect(incoming)
        guard inspected.manifest.documentID == documentID, inspected.manifest.notebookID == metadata.id,
              try SnapshotDigest.package(package, metadata: metadata) == expectedLocal else { throw WorkspaceFailure.staleRevision }
        guard try createAutomaticBackup(metadata: metadata, minimumInterval: 0) != nil else { throw WorkspaceFailure.staleRevision }
        let parent = package.deletingLastPathComponent(), name = "\(documentID).cloudPrevious"
        let previous = try NativeArchive.fileURL(name, in: parent)
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
        _ = try FileManager.default.replaceItemAt(package, withItemAt: incoming, backupItemName: name, options: .withoutDeletingBackupItem)
        invalidateDerivedSearch()
        // The committed .nnbackup retains the old data; avoid a second full copy.
        try? FileManager.default.removeItem(at: previous)
    }
}
