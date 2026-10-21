import Foundation

public enum NativeRecoveryScan {
    /// Discover packages in a user-selected folder. Never traverse symbolic
    /// links or modify a source; each candidate is validated by NativeImport.
    public static func packages(in root: URL) throws -> [URL] {
        var pending: [(URL, Int)] = [(root, 0)], result: [URL] = []
        var visited = 0
        while let (directory, depth) = pending.popLast() {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path) {
                result.append(directory); guard result.count <= 200 else { throw NativeArchiveFailure.limit }; continue
            }
            guard depth < 4 else { continue }
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                visited += 1; guard visited <= 50_000 else { throw NativeArchiveFailure.limit }
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true && values.isSymbolicLink != true { pending.append((child, depth + 1)) }
            }
        }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
