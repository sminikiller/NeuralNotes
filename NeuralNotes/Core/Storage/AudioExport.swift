import Foundation

public final class AudioExportBundle: Sendable {
    public let directory: URL
    public let files: [URL]
    init(directory: URL, files: [URL]) { self.directory = directory; self.files = files }
    public func removeTemporaryFiles() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    deinit { try? removeTemporaryFiles() }
}

private struct AudioExportManifest: Codable { var format = 2; let session: AudioSession }

public extension DocumentWorkspace {
    /// Exact active parts (CAF or verified AAC), without further re-encoding.
    /// Codec/bitrate/original size travel in the JSON alongside the timeline.
    /// Pause/resume boundaries remain
    /// explicit in the playlist and JSON; no multi-hour file becomes one Data.
    func exportAudioSession(_ id: UUID) throws -> AudioExportBundle {
        guard let original = try catalog().sessions.first(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        guard original.state == "finished", original.trashedAt == nil, !original.segments.isEmpty, original.segments.count <= 1000 else { throw WorkspaceFailure.staleRevision }
        var total: Int64 = 0, sources: [(URL, Int)] = []
        for segment in original.segments {
            try Task.checkCancellation()
            let file = try url(segment.file), info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, size > 0,
                  segment.start.isFinite, segment.duration.isFinite, segment.start >= 0, segment.duration >= 0 else { throw LibraryFailure.corruptDocument }
            guard Int64(size) <= 16 * 1024 * 1024 * 1024 - total else { throw NativeArchiveFailure.limit }; total += Int64(size)
            sources.append((file, size))
        }
        let temporary = FileManager.default.temporaryDirectory
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: temporary.path)
        if let available = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value, available < total + 64 * 1024 * 1024 {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let directory = temporary.appendingPathComponent("NN-AudioExport-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
        var files: [URL] = [], session = original, mapping: [String: String] = [:], playlist = "#EXTM3U\n"
        for i in sources.indices {
            try Task.checkCancellation()
            let source = sources[i].0, suffix = source.pathExtension.lowercased()
            let ext = ["m4a", "mp3", "wav", "caf", "aac", "aif", "aiff", "flac", "mp4"].contains(suffix) ? suffix : "audio"
            let clock = TranscriptText.clock(session.segments[i].start).replacingOccurrences(of: ":", with: "-")
            let name = String(format: "%03d", i + 1) + "-" + clock + "." + ext
            let destination = directory.appendingPathComponent(name)
            try Self.copyAudioExport(source, to: destination, expectedSize: sources[i].1)
            mapping[session.segments[i].file] = mapping[session.segments[i].file] ?? name
            session.segments[i].file = name; files.append(destination)
            playlist += "#EXTINF:\(session.segments[i].duration),Parte \(i + 1)\n\(name)\n"
        }
        if var chunks = session.transcriptionChunks {
            for i in chunks.indices {
                guard let mapped = mapping[chunks[i].file] else { throw LibraryFailure.corruptDocument }; chunks[i].file = mapped
            }; session.transcriptionChunks = chunks
        }
        func textFile(_ name: String, text: String) throws {
            let file = directory.appendingPathComponent(name); try text.write(to: file, atomically: true, encoding: .utf8); files.append(file)
        }
        if original.hasTranscriptText {
            try textFile("Trascrizione.txt", text: TranscriptText.export(title: original.title, segments: original.readableTranscript, complete: original.hasCompletedTranscript))
            try textFile("Trascrizione.md", text: TranscriptChapters.markdown(session: original))
        }
        try textFile("Registrazione.m3u8", text: playlist)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let manifest = try encoder.encode(AudioExportManifest(session: session))
        guard manifest.count <= 16 * 1024 * 1024 else { throw WorkspaceFailure.oversizedMetadata }
        let metadata = directory.appendingPathComponent("Registrazione.json"); try manifest.write(to: metadata, options: .atomic); files.append(metadata)
        try Task.checkCancellation(); complete = true
        return AudioExportBundle(directory: directory, files: files)
    }
    private static func copyAudioExport(_ source: URL, to destination: URL, expectedSize: Int) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        var count = 0
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation(); count += data.count
            guard count <= expectedSize else { throw WorkspaceFailure.staleRevision }; try output.write(contentsOf: data)
        }
        guard count == expectedSize else { throw WorkspaceFailure.staleRevision }; try output.synchronize()
    }
}
