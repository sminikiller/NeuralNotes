import Foundation

public enum NativeArchiveFailure: LocalizedError {
    case corrupt, limit, invalidEntry(String), checksum(String), truncated, trailingBytes
    public var errorDescription: String? {
        switch self {
        case .corrupt: return "Backup incompleto, danneggiato o con percorsi non validi. Il file originale è stato conservato."
        case .limit: return "Il backup supera i limiti supportati (16 GB o 50.000 file)."
        case .invalidEntry(let path): return "Voce del backup non valida: \(path). Il file originale è stato conservato."
        case .checksum(let path): return "Il controllo di integrità del backup non corrisponde per \(path). Il file originale è stato conservato."
        case .truncated: return "Il backup termina prima della fine dei dati attesi. Il file originale è stato conservato."
        case .trailingBytes: return "Il backup contiene dati oltre la fine dell’archivio. Il file originale è stato conservato."
        }
    }
}

/// Streaming container, without compression: JSON directory + file bytes + CRC32
/// checksums in the directory. Large recordings never become a single Data value.
public enum NativeArchive {
    private struct Entry: Codable { let path: String; let size: UInt64; let checksum: UInt32 }
    private struct Header: Codable { let version: Int; let entries: [Entry] }
    private static let magic = Data("NNBOOK01".utf8)
    private static let maximumSize: UInt64 = 16 * 1024 * 1024 * 1024
    private static let chunkSize = 256 * 1024
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = (c & 1 == 1) ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func fileURL(_ path: String, in root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard root.isFileURL, !path.contains("\\"), !path.contains(":"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw WorkspaceFailure.invalidPath
        }
        var result = root.standardizedFileURL.resolvingSymlinksInPath()
        for part in parts {
            result.appendPathComponent(String(part), isDirectory: false)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: result.path)) != nil {
                throw WorkspaceFailure.invalidPath
            }
        }
        return result
    }

    public static func write(package: URL, metadata: Notebook, to destination: URL) throws {
        var sources: [(String, URL)] = []
        for file in try PackageFiles.list(in: package) {
            guard allowed(file.path) else { throw NativeArchiveFailure.invalidEntry(file.path) }
            if file.path != "metadata.json" { sources.append((file.path, file.url)) }
        }
        sources.sort { $0.0 < $1.0 }
        guard sources.count < 50_000 else { throw NativeArchiveFailure.limit }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(metadata)
        var entries: [Entry] = []
        var total = UInt64(metadataData.count)
        for (path, url) in sources {
            try Task.checkCancellation()
            let size = UInt64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size <= maximumSize, total <= maximumSize - size else { throw NativeArchiveFailure.limit }
            total += size
            entries.append(Entry(path: path, size: size, checksum: try checksum(url)))
        }
        entries.append(Entry(path: "metadata.json", size: UInt64(metadataData.count), checksum: crc(metadataData)))
        let header = try encoder.encode(Header(version: 1, entries: entries))
        guard header.count <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        do {
            defer { try? output.close() }
            try output.write(contentsOf: magic)
            let length = UInt64(header.count)
            try output.write(contentsOf: Data((0..<8).map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) }))
            try output.write(contentsOf: header)
            for (index, item) in sources.enumerated() {
                let input = try FileHandle(forReadingFrom: item.1)
                defer { try? input.close() }
                let result = try transfer(input: input, output: output, count: entries[index].size)
                guard result == entries[index].checksum,
                      (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw WorkspaceFailure.staleRevision }
            }
            try output.write(contentsOf: metadataData)
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Destination must be fresh. A failed extraction removes only that new directory.
    public static func extract(from source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try exact(input, count: 8) == magic else { throw NativeArchiveFailure.corrupt }
        let bytes = try exact(input, count: 8)
        let length = bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
        guard length > 0, length <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.corrupt }
        let header = try JSONDecoder().decode(Header.self, from: exact(input, count: Int(length)))
        guard header.version == 1, !header.entries.isEmpty, header.entries.count <= 50_000,
              Set(header.entries.map(\.path)).count == header.entries.count else { throw NativeArchiveFailure.corrupt }
        var total: UInt64 = 0
        // Also reject case-folded collisions, including on case-insensitive Apple volumes.
        var normalized = Set<String>()
        for entry in header.entries {
            guard allowed(entry.path), normalized.insert(entry.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw NativeArchiveFailure.invalidEntry(entry.path)
            }
            _ = try fileURL(entry.path, in: destination)
            guard entry.size <= maximumSize, total <= maximumSize - entry.size else { throw NativeArchiveFailure.limit }
            total += entry.size
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for name in ["pages", "drawings", "images", "audio", "attachments", "artifacts"] {
                try FileManager.default.createDirectory(at: destination.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            for entry in header.entries {
                try Task.checkCancellation()
                let url = try fileURL(entry.path, in: destination)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let output = try FileHandle(forWritingTo: url)
                defer { try? output.close() }
                guard try transfer(input: input, output: output, count: entry.size) == entry.checksum else {
                    throw NativeArchiveFailure.checksum(entry.path)
                }
            }
            guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw NativeArchiveFailure.trailingBytes }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func allowed(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 1 { return ["manifest.json", "manifest.previous.json", "catalog.json", "metadata.json"].contains(path) }
        return parts.count >= 2 && ["pages", "drawings", "images", "audio", "attachments", "artifacts", "recovery"].contains(String(parts[0]))
    }

    private static func exact(_ input: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let next = try input.read(upToCount: count - data.count), !next.isEmpty else { throw NativeArchiveFailure.truncated }
            data.append(next)
        }
        return data
    }

    private static func transfer(input: FileHandle, output: FileHandle, count: UInt64) throws -> UInt32 {
        var remaining = count, value = UInt32.max
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try exact(input, count: Int(min(UInt64(chunkSize), remaining)))
            value = update(value, chunk)
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
        return value ^ UInt32.max
    }

    private static func checksum(_ url: URL) throws -> UInt32 {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var value = UInt32.max
        while let bytes = try file.read(upToCount: chunkSize), !bytes.isEmpty {
            try Task.checkCancellation(); value = update(value, bytes)
        }
        return value ^ UInt32.max
    }
    private static func crc(_ bytes: Data) -> UInt32 { update(UInt32.max, bytes) ^ UInt32.max }
    private static func update(_ value: UInt32, _ bytes: Data) -> UInt32 {
        bytes.reduce(value) { table[Int(($0 ^ UInt32($1)) & 255)] ^ ($0 >> 8) }
    }
}
