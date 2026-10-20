import Foundation

/// Walk names relative to each directory instead of subtracting URL component
/// counts. Directory markers and Darwin /var aliases must never alter archive names.
enum PackageFiles {
    struct File {
        let path: String
        let url: URL
    }

    static func list(in root: URL) throws -> [File] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard root.isFileURL, try root.resourceValues(forKeys: keys).isDirectory == true else {
            throw LibraryFailure.corruptDocument
        }
        var pending: [(URL, String, Int)] = [(root, "", 0)]
        var result: [File] = []
        var count = 0
        while let (directory, prefix, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard depth <= 64 else { throw NativeArchiveFailure.limit }
            let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            for child in children {
                count += 1
                guard count <= 50_000 else { throw NativeArchiveFailure.limit }
                let name = child.lastPathComponent
                let values = try child.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { throw WorkspaceFailure.invalidPath }
                // Finder/resource-fork sidecars are not NeuralNotes content.
                if name == ".DS_Store" || name.hasPrefix("._") { continue }
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                _ = try NativeArchive.fileURL(path, in: root)
                if values.isDirectory == true { pending.append((child, path, depth + 1)) }
                else if values.isRegularFile == true { result.append(File(path: path, url: child)) }
                else { throw NativeArchiveFailure.invalidEntry(path) }
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
