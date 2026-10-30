import Foundation

/// Undo history is session-local, outside the document and its backups. The
/// first builder in this app process snapshots the old owned directories;
/// subsequent builders never scan/delete another window's active history.
enum PageEditHistoryRoot {
    static let managed: Result<URL, Error> = Result {
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw CocoaError(.fileNoSuchFile) }
        let expected = support.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("NeuralNotesEditHistory", isDirectory: true)
        if manager.fileExists(atPath: expected.path), try expected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw WorkspaceFailure.invalidPath }
        let root = expected.standardizedFileURL.resolvingSymlinksInPath()
        guard root.deletingLastPathComponent() == support.standardizedFileURL.resolvingSymlinksInPath() else { throw WorkspaceFailure.invalidPath }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let stale = try orphanCandidates(in: root)
        Task.detached(priority: .utility) { discard(stale, in: root) }
        return root
    }
    /// Only UUID directories owned by this feature are eligible. This never
    /// enumerates notebooks, user backup folders or explicitly injected roots.
    static func orphanCandidates(in root: URL) throws -> [URL] {
        let folder = root.standardizedFileURL.resolvingSymlinksInPath()
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("edit-"), UUID(uuidString: String(name.dropFirst(5))) != nil else { return false }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values.isDirectory == true && values.isSymbolicLink != true &&
                url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == folder
        }
    }
    static func discard(_ candidates: [URL], in root: URL) {
        let folder = root.standardizedFileURL.resolvingSymlinksInPath()
        for url in candidates {
            let name = url.lastPathComponent
            guard name.hasPrefix("edit-"), UUID(uuidString: String(name.dropFirst(5))) != nil,
                  url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == folder,
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
