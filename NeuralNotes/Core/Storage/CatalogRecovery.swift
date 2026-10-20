import Foundation

public struct CatalogRecoveryStatus: Sendable {
    public let needsRecovery: Bool
    public let canRestore: Bool
}

enum CatalogRecovery {
    static let previousPath = "recovery/catalog.previous.json"
    static let retainedPath = "recovery/catalog-retained-media.json"
    static let mediaFolders: Set<String> = ["drawings", "images", "audio", "attachments"]

    static func decode(_ data: Data, package: URL, requireMedia: Bool = false) throws -> DocumentCatalog {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let version = try decoder.decode(Header.self, from: data).schemaVersion
        guard version == 1 else { throw LibraryFailure.unsupportedVersion(version) }
        let value = try decoder.decode(DocumentCatalog.self, from: data)
        guard value.defaultPageTemplate?.appearance.isValid != false,
              value.editorWorkspaces?.isValid != false, value.coverDesign?.isValid != false,
              Set(value.sessions.map(\.id)).count == value.sessions.count else { throw LibraryFailure.corruptDocument }
        for path in references(value) {
            let file = try NativeArchive.fileURL(path, in: package)
            if requireMedia, try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile != true { throw LibraryFailure.corruptDocument }
        }
        return value
    }
    static func references(_ value: DocumentCatalog) -> [String] {
        value.attachments.map(\.file) + value.sessions.flatMap { $0.segments.map(\.file) } + [value.coverImageFile].compactMap { $0 }
    }
    static func read(_ path: String, package: URL, requireMedia: Bool = false) throws -> DocumentCatalog {
        let file = try NativeArchive.fileURL(path, in: package)
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        return try decode(Data(contentsOf: file), package: package, requireMedia: requireMedia)
    }
    static func preserveCurrent(in package: URL) throws {
        let current = try NativeArchive.fileURL("catalog.json", in: package)
        guard FileManager.default.fileExists(atPath: current.path) else { return }
        // A broken/newer catalog must not overwrite the last readable copy.
        guard (try? read("catalog.json", package: package)) != nil else { return }
        let destination = try NativeArchive.fileURL(previousPath, in: package)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: current).write(to: destination, options: .atomic)
    }
    static func retainedMedia(in package: URL) throws -> [String] {
        let file = try NativeArchive.fileURL(retainedPath, in: package)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: file))
        guard paths.count <= 50_000 else { throw NativeArchiveFailure.limit }
        for path in paths {
            guard let folder = path.split(separator: "/").first, mediaFolders.contains(String(folder)) else { throw WorkspaceFailure.invalidPath }
            _ = try NativeArchive.fileURL(path, in: package)
        }
        return paths
    }
}

extension DocumentWorkspace {
    public func catalogRecoveryStatus() throws -> CatalogRecoveryStatus {
        let current = try url("catalog.json"), previous = try url(CatalogRecovery.previousPath)
        let hasCurrent = FileManager.default.fileExists(atPath: current.path)
        let hasPrevious = FileManager.default.fileExists(atPath: previous.path)
        let readable = hasCurrent ? (try? CatalogRecovery.read("catalog.json", package: package, requireMedia: true)) != nil : !hasPrevious
        let recoverable = hasPrevious && (try? CatalogRecovery.read(CatalogRecovery.previousPath, package: package, requireMedia: true)) != nil
        return CatalogRecoveryStatus(needsRecovery: !readable, canRestore: recoverable)
    }
    /// Explicit recovery, never automatic rollback. Preserve both source bytes
    /// and all media present at recovery before committing the older catalog.
    public func restorePreviousCatalog() throws {
        let current = try url("catalog.json")
        if FileManager.default.fileExists(atPath: current.path) {
            do { _ = try CatalogRecovery.read("catalog.json", package: package) }
            catch LibraryFailure.unsupportedVersion(let version) { throw LibraryFailure.unsupportedVersion(version) }
            catch { }
        }
        _ = try CatalogRecovery.read(CatalogRecovery.previousPath, package: package, requireMedia: true)
        let bytes = try Data(contentsOf: url(CatalogRecovery.previousPath))
        let recovery = try url("recovery")
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: current.path) {
            try FileManager.default.copyItem(at: current, to: recovery.appendingPathComponent("catalog-interrupted-\(UUID()).json"))
        }
        var retained = Set(try CatalogRecovery.retainedMedia(in: package))
        for file in try PackageFiles.list(in: package) {
            if let folder = file.path.split(separator: "/").first, CatalogRecovery.mediaFolders.contains(String(folder)) { retained.insert(file.path) }
        }
        try JSONEncoder().encode(retained.sorted()).write(to: url(CatalogRecovery.retainedPath), options: .atomic)
        try bytes.write(to: current, options: .atomic)
    }
}
