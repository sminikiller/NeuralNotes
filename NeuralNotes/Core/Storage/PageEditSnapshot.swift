import Foundation

/// Owns undo media outside the package. Cleanup of unused notebook files cannot
/// invalidate a bulk edit's undo, and no array of native drawings stays in RAM.
public final class PageEditSnapshot: Sendable {
    public let documentID: UUID
    public let directory: URL
    public let pageIDs: [UUID]
    public let byteCount: Int64
    public var residentCost: Int { 1024 + pageIDs.count * 32 + media.reduce(0) { $0 + $1.utf8.count + 64 } }
    private let drawings: Set<UUID>, media: Set<String>, ids: Set<UUID>
    fileprivate init(documentID: UUID, directory: URL, pageIDs: [UUID], drawings: Set<UUID>, media: Set<String>, bytes: Int64) {
        self.documentID = documentID; self.directory = directory; self.pageIDs = pageIDs
        self.drawings = drawings; self.media = media; self.byteCount = bytes; ids = Set(pageIDs)
    }
    public func page(_ id: UUID) throws -> PageSnapshot {
        guard ids.contains(id) else { throw LibraryFailure.missingItem }
        let file = try boundedFile("pages/\(id).json", maximum: 16 << 20)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: file))
        guard value.id == id else { throw LibraryFailure.corruptDocument }
        try PageValidation.validate(value); return value
    }
    public func drawingURL(_ id: UUID) throws -> URL? {
        guard ids.contains(id) else { throw LibraryFailure.missingItem }
        return try drawings.contains(id) ? boundedFile("ink/\(id).drawing", maximum: 100 << 20) : nil
    }
    /// Called by the serialized document writer before its journal commits.
    /// Existing immutable files are never overwritten.
    func restoreMedia(in package: URL) throws {
        for path in media {
            try Task.checkCancellation()
            let source = try boundedFile("media/\(path)", maximum: 100 << 20)
            let target = try NativeArchive.fileURL(path, in: package)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }
    private func boundedFile(_ path: String, maximum: Int) throws -> URL {
        let file = try NativeArchive.fileURL(path, in: directory)
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, (0...maximum).contains(size) else { throw NativeArchiveFailure.limit }
        return file
    }
    deinit {
        // Releasing old history must not delete thousands of files on the UI
        // thread while the user is starting the next stroke.
        let folder = directory
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }
}

public actor PageEditSnapshotBuilder {
    private let documentID: UUID, directory: URL
    private var ids: [UUID] = [], idSet = Set<UUID>(), drawings = Set<UUID>(), media = Set<String>()
    private var bytes: Int64 = 0, finished = false
    public init(documentID: UUID, parent: URL? = nil) throws {
        self.documentID = documentID
        let manager = FileManager.default
        guard let support = parent ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("NeuralNotesEditHistory") else { throw CocoaError(.fileNoSuchFile) }
        let root = support.standardizedFileURL.resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let created = root.appendingPathComponent("edit-\(UUID())", isDirectory: true)
        directory = created
        try manager.createDirectory(at: created, withIntermediateDirectories: false)
        var ready = false
        defer { if !ready { try? manager.removeItem(at: created) } }
        for name in ["pages", "ink", "media"] { try manager.createDirectory(at: created.appendingPathComponent(name), withIntermediateDirectories: false) }
        ready = true
    }
    /// Append one state, then release its Data before asking for the next page.
    public func append(_ page: PageSnapshot, drawing: Data?, sourcePackage: URL) throws {
        try Task.checkCancellation()
        guard !finished, ids.count < PageEditRecovery.maximumPages, !idSet.contains(page.id),
              (drawing?.count ?? 0) <= 100 << 20 else { throw NativeArchiveFailure.limit }
        try PageValidation.validate(page)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(page)
        guard data.count <= 16 << 20 else { throw NativeArchiveFailure.limit }
        try reserve(Int64(data.count) + Int64(drawing?.count ?? 0))
        for path in Set(page.images.map(\.file)).subtracting(media) {
            guard path.hasPrefix("images/"), media.count < 50000 else { throw WorkspaceFailure.invalidPath }
            let source = try NativeArchive.fileURL(path, in: sourcePackage)
            let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, (0...100 << 20).contains(size) else { throw NativeArchiveFailure.limit }
            try reserve(Int64(size))
            let target = try NativeArchive.fileURL("media/\(path)", in: directory)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            media.insert(path); bytes += Int64(size)
        }
        if let drawing {
            try drawing.write(to: directory.appendingPathComponent("ink/\(page.id).drawing"), options: .atomic)
            drawings.insert(page.id)
        }
        try data.write(to: directory.appendingPathComponent("pages/\(page.id).json"), options: .atomic)
        ids.append(page.id); idSet.insert(page.id); bytes += Int64(data.count) + Int64(drawing?.count ?? 0)
    }
    public func finish() throws -> PageEditSnapshot {
        try Task.checkCancellation()
        guard !finished, !ids.isEmpty else { throw WorkspaceFailure.emptyDocument }
        finished = true
        return PageEditSnapshot(documentID: documentID, directory: directory, pageIDs: ids, drawings: drawings, media: media, bytes: bytes)
    }
    private func reserve(_ additional: Int64) throws {
        let info = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        if let available = info[.systemFreeSize] as? NSNumber, available.int64Value < additional + (64 << 20) {
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }
    deinit {
        if !finished {
            let folder = directory
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
