import Foundation

public extension DocumentWorkspace {
    /// File copy instead of loading an entire lecture into memory. The catalog
    /// is committed only after the independent audio file exists.
    func importAudio(from source: URL, duration: Double, title: String) throws -> AudioSession {
        guard source.isFileURL, duration.isFinite, duration > 0, duration <= 7 * 86400 else { throw LibraryFailure.corruptDocument }
        let name = try LibraryName.validated(title)
        let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let length = size.fileSize, length > 0, length <= 2_000_000_000 else { throw WorkspaceFailure.oversizedImport }
        let allowed = ["m4a", "mp3", "wav", "caf", "aac", "aif", "aiff", "flac", "mp4"]
        let suffix = source.pathExtension.lowercased()
        guard allowed.contains(suffix) else { throw LibraryFailure.corruptDocument }
        var session = AudioSession(title: name)
        let relative = "audio/\(session.id).\(suffix)", destination = try url(relative)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            copied += chunk.count
            guard copied <= length else { throw LibraryFailure.corruptDocument }
            try output.write(contentsOf: chunk)
        }
        guard copied == length else { throw LibraryFailure.corruptDocument }
        try output.synchronize()
        var segment = AudioTimelineSegment(file: relative, start: 0, hostStart: 0)
        segment.duration = duration; segment.endReason = "Audio importato"
        session.segments = [segment]; session.state = "finished"; session.revision = 1
        try saveSession(session); return session
    }
}
