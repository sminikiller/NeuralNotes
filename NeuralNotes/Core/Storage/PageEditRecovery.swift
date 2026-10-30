import Foundation

/// Only header references are resident: drawings/media are immutable package
/// files committed before this journal. This supports a streamed notebook edit.
struct PageEditJournal: Codable {
    struct Entry: Codable {
        var pageID: UUID
        var expectedRevision: Int?
    }
    var format = 1
    var operationID: UUID
    var documentID: UUID
    var notebookID: UUID
    var oldOrder: [UUID]
    var newOrder: [UUID]
    var entries: [Entry]
    var directory: String { "recovery/page-edit-\(operationID.uuidString)" }
    func header(_ id: UUID) -> String { "\(directory)/\(id.uuidString).json" }
}

enum PageEditRecovery {
    static let path = "recovery/page-edit.json"
    static let maximumPages = 5000

    /// First validate EVERY page; then complete the durable forward commit.
    /// No cancellation/error removes this pointer until all pages/order commit.
    static func recover(in package: URL) throws {
        let pointer = try NativeArchive.fileURL(path, in: package)
        guard FileManager.default.fileExists(atPath: pointer.path) else { return }
        let journal: PageEditJournal = try read(path, package: package)
        let manifest: DocumentManifest = try read("manifest.json", package: package)
        try validate(journal, manifest: manifest)
        for entry in journal.entries {
            try Task.checkCancellation()
            let next: PageSnapshot = try read(journal.header(entry.pageID), package: package)
            try validate(entry, next: next, package: package)
        }
        // A crash from here forward leaves the validated pointer in place and
        // accepts a mixture of expected and already-written headers next time.
        for entry in journal.entries {
            try Task.checkCancellation()
            let source = try NativeArchive.fileURL(journal.header(entry.pageID), in: package)
            let destination = try NativeArchive.fileURL("pages/\(entry.pageID).json", in: package)
            try Data(contentsOf: source).write(to: destination, options: .atomic)
        }
        var updated = manifest; updated.pageIDs = journal.newOrder
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(updated).write(to: NativeArchive.fileURL("manifest.json", in: package), options: .atomic)
        try FileManager.default.removeItem(at: pointer)
        // Cleanup failure cannot roll back an edit that already committed.
        try? FileManager.default.removeItem(at: NativeArchive.fileURL(journal.directory, in: package))
    }
    private static func validate(_ journal: PageEditJournal, manifest: DocumentManifest) throws {
        let old = Set(journal.oldOrder), new = Set(journal.newOrder)
        guard journal.format == 1, manifest.schemaVersion == 1,
              journal.documentID == manifest.documentID, journal.notebookID == manifest.notebookID,
              (1...maximumPages).contains(journal.entries.count),
              (1...maximumPages).contains(journal.oldOrder.count), (1...maximumPages).contains(journal.newOrder.count),
              old.count == journal.oldOrder.count, new.count == journal.newOrder.count,
              Set(journal.entries.map(\.pageID)).count == journal.entries.count,
              Set(journal.entries.map(\.pageID)).isSubset(of: old.union(new)),
              manifest.pageIDs == journal.oldOrder || manifest.pageIDs == journal.newOrder else { throw LibraryFailure.corruptDocument }
        // Every newly published page must have its validated prepared header.
        guard new.subtracting(old).isSubset(of: Set(journal.entries.map(\.pageID))) else { throw LibraryFailure.corruptDocument }
    }
    private static func validate(_ entry: PageEditJournal.Entry, next: PageSnapshot, package: URL) throws {
        try PageValidation.validate(next)
        guard next.id == entry.pageID else { throw LibraryFailure.corruptDocument }
        if let expected = entry.expectedRevision {
            guard expected >= 0, expected < Int.max, next.revision == expected + 1 else { throw WorkspaceFailure.staleRevision }
        } else if next.revision != 0 { throw WorkspaceFailure.staleRevision }
        let currentPath = "pages/\(entry.pageID).json"
        let currentFile = try NativeArchive.fileURL(currentPath, in: package)
        if FileManager.default.fileExists(atPath: currentFile.path) {
            let current: PageSnapshot = try read(currentPath, package: package)
            guard current.id == next.id, current == next || current.revision == entry.expectedRevision else { throw WorkspaceFailure.staleRevision }
        } else if entry.expectedRevision != nil { throw LibraryFailure.missingItem }
        let assets = [next.drawingFile, next.previousDrawingFile, next.pdfFile].compactMap { $0 } + next.images.map(\.file)
        for drawing in [next.drawingFile, next.previousDrawingFile].compactMap({ $0 }) {
            guard drawing.hasPrefix("drawings/"), drawing.hasSuffix(".drawing") else { throw LibraryFailure.corruptDocument }
        }
        for asset in assets {
            let file = try NativeArchive.fileURL(asset, in: package)
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LibraryFailure.corruptDocument }
        }
    }
    private static func read<T: Decodable>(_ path: String, package: URL) throws -> T {
        let file = try NativeArchive.fileURL(path, in: package)
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, (0...16 * 1024 * 1024).contains(size) else { throw NativeArchiveFailure.limit }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: file))
    }
}
