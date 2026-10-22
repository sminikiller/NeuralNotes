import Foundation
#if canImport(zlib)
import zlib
#endif

/// CRC-32 (IEEE 802.3), the checksum stored in `.nnbackup` archives. The system
/// zlib is used when the SDK exposes it; otherwise slicing by eight bytes over raw
/// pointers keeps the exact same values with far fewer operations per byte.
enum CRC32 {
    /// Eight 256-entry tables: table k advances the CRC by k extra zero bytes.
    static let tables: [UInt32] = {
        var tables = [UInt32](repeating: 0, count: 8 * 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
            tables[index] = value
        }
        for slice in 1..<8 {
            for index in 0..<256 {
                let previous = tables[(slice - 1) * 256 + index]
                tables[slice * 256 + index] = (previous >> 8) ^ tables[Int(previous & 0xFF)]
            }
        }
        return tables
    }()

    /// Continues a running register; callers keep the usual pre and post inversion.
    static func update(_ value: UInt32, _ bytes: UnsafeRawBufferPointer) -> UInt32 {
        guard let start = bytes.baseAddress, bytes.count > 0 else { return value }
        #if canImport(zlib)
        // zlib takes and returns the finalized CRC: convert from and back to the running register.
        var crc = uLong(value ^ UInt32.max), offset = 0
        while offset < bytes.count {
            let length = min(bytes.count - offset, 1 << 30)
            crc = crc32(crc, (start + offset).assumingMemoryBound(to: Bytef.self), uInt(length))
            offset += length
        }
        return UInt32(truncatingIfNeeded: crc) ^ UInt32.max
        #else
        return sliced(value, start.assumingMemoryBound(to: UInt8.self), bytes.count)
        #endif
    }

    static func sliced(_ value: UInt32, _ p: UnsafePointer<UInt8>, _ count: Int) -> UInt32 {
        tables.withUnsafeBufferPointer { buffer -> UInt32 in
            let t = buffer.baseAddress!
            var crc = value, i = 0
            while i &+ 8 <= count {
                let one = (UInt32(p[i]) | UInt32(p[i &+ 1]) << 8 | UInt32(p[i &+ 2]) << 16 | UInt32(p[i &+ 3]) << 24) ^ crc
                let two = UInt32(p[i &+ 4]) | UInt32(p[i &+ 5]) << 8 | UInt32(p[i &+ 6]) << 16 | UInt32(p[i &+ 7]) << 24
                crc = t[1792 &+ Int(one & 0xFF)] ^ t[1536 &+ Int((one >> 8) & 0xFF)] ^ t[1280 &+ Int((one >> 16) & 0xFF)] ^ t[1024 &+ Int(one >> 24)]
                    ^ t[768 &+ Int(two & 0xFF)] ^ t[512 &+ Int((two >> 8) & 0xFF)] ^ t[256 &+ Int((two >> 16) & 0xFF)] ^ t[Int(two >> 24)]
                i = i &+ 8
            }
            while i < count {
                crc = t[Int((crc ^ UInt32(p[i])) & 0xFF)] ^ (crc >> 8)
                i = i &+ 1
            }
            return crc
        }
    }

    static func update(_ value: UInt32, _ data: Data) -> UInt32 { data.withUnsafeBytes { update(value, $0) } }
    static func checksum(_ data: Data) -> UInt32 { update(UInt32.max, data) ^ UInt32.max }
}

/// Checksums of package files that did not change since an earlier backup: large
/// PDFs, audio and images are immutable once stored, so repeated backups only copy
/// them. The table is kept in Caches, so it also survives app restarts.
final class ArchiveChecksumCache: @unchecked Sendable {
    static let shared = ArchiveChecksumCache(file: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("NeuralNotes", isDirectory: true).appendingPathComponent("archive-checksums.json"))
    private struct Key: Codable, Hashable { let path: String; let size: UInt64; let modified: Date }
    private struct Entry: Codable { let key: Key; let checksum: UInt32 }
    private let lock = NSLock()
    private let file: URL?
    private var values: [Key: UInt32] = [:]
    private var loaded = false, dirty = false

    init(file: URL?) { self.file = file }

    func checksum(path: String, size: UInt64, modified: Date?) -> UInt32? {
        guard let modified else { return nil }
        lock.lock(); defer { lock.unlock() }
        load()
        return values[Key(path: path, size: size, modified: modified)]
    }

    func store(_ checksum: UInt32, path: String, size: UInt64, modified: Date?) {
        guard let modified else { return }
        lock.lock(); defer { lock.unlock() }
        load()
        if values.count >= 20_000 { values.removeAll(keepingCapacity: true) }
        values[Key(path: path, size: size, modified: modified)] = checksum; dirty = true
    }

    /// Written once per archive, never per file: a missing or damaged table only costs a recalculation.
    func persist() {
        lock.lock(); defer { lock.unlock() }
        guard dirty, let file else { return }
        let entries = values.map { Entry(key: $0.key, checksum: $0.value) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic); dirty = false
        } catch { }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file), data.count <= 16 * 1024 * 1024,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for entry in entries.prefix(20_000) { values[entry.key] = entry.checksum }
    }
}
