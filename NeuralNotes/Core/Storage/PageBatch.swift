import Foundation

public struct PageMutation: Sendable {
    public var page: PageSnapshot
    public var expectedRevision: Int
    public var drawing: Data
    public init(page: PageSnapshot, expectedRevision: Int, drawing: Data) {
        self.page = page; self.expectedRevision = expectedRevision; self.drawing = drawing
    }
}

struct PageBatchJournal: Codable {
    struct Entry: Codable { var expectedRevision: Int; var page: PageSnapshot }
    var format = 1
    var documentID: UUID
    var notebookID: UUID
    var entries: [Entry]
}

enum PageBatchRecovery {
    static let path = "recovery/page-batch.json"
    /// The durable journal is the commit point. A crash after either page write
    /// completes the whole operation on reopening, before any new page edit.
    static func recover(in package: URL) throws {
        let file = try NativeArchive.fileURL(path, in: package)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let journal = try decoder.decode(PageBatchJournal.self, from: Data(contentsOf: file))
        let manifestFile = try NativeArchive.fileURL("manifest.json", in: package)
        guard (try manifestFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        let manifest = try decoder.decode(DocumentManifest.self, from: Data(contentsOf: manifestFile))
        guard journal.format == 1, manifest.schemaVersion == 1, manifest.documentID == journal.documentID, manifest.notebookID == journal.notebookID,
              Set(manifest.pageIDs).count == manifest.pageIDs.count,
              (2...8).contains(journal.entries.count), Set(journal.entries.map { $0.page.id }).count == journal.entries.count else { throw LibraryFailure.corruptDocument }
        // Validate every destination and every referenced asset before touching
        // even the first page. A malformed recovery file cannot partially apply.
        for entry in journal.entries {
            try PageValidation.validate(entry.page)
            guard manifest.pageIDs.contains(entry.page.id), entry.expectedRevision >= 0, entry.expectedRevision < Int.max,
                  entry.page.revision == entry.expectedRevision + 1 else { throw WorkspaceFailure.staleRevision }
            guard let drawing = entry.page.drawingFile, drawing.hasPrefix("drawings/\(entry.page.id)-"), drawing.hasSuffix(".drawing") else { throw LibraryFailure.corruptDocument }
            let pageFile = try NativeArchive.fileURL("pages/\(entry.page.id).json", in: package)
            guard (try pageFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
            let current = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: pageFile))
            guard current.id == entry.page.id, current.revision == entry.expectedRevision || current == entry.page else { throw WorkspaceFailure.staleRevision }
            for path in [entry.page.drawingFile, entry.page.previousDrawingFile, entry.page.pdfFile].compactMap({ $0 }) + entry.page.images.map(\.file) {
                let url = try NativeArchive.fileURL(path, in: package)
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LibraryFailure.corruptDocument }
            }
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        for entry in journal.entries {
            try encoder.encode(entry.page).write(to: NativeArchive.fileURL("pages/\(entry.page.id).json", in: package), options: .atomic)
        }
        try FileManager.default.removeItem(at: file)
    }
}

public extension DocumentWorkspace {
    @discardableResult
    func applyPageBatch(_ changes: [PageMutation]) throws -> [PageSnapshot] {
        let manifest = try manifest()
        guard (2...8).contains(changes.count), Set(changes.map { $0.page.id }).count == changes.count,
              changes.reduce(0, { $0 + min($1.drawing.count, 65 * 1024 * 1024) }) <= 64 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        var entries: [PageBatchJournal.Entry] = []
        // Check the complete batch before creating new snapshots.
        for change in changes {
            try PageValidation.validate(change.page)
            let current = try pageSnapshot(change.page.id)
            guard current.revision == change.expectedRevision, change.expectedRevision < Int.max else { throw WorkspaceFailure.staleRevision }
            for path in [change.page.pdfFile, current.drawingFile].compactMap({ $0 }) + change.page.images.map(\.file) {
                let file = try url(path)
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LibraryFailure.corruptDocument }
            }
            var next = change.page; next.revision = current.revision + 1
            next.lastEditedAt = Date().timeIntervalSince1970
            next.previousDrawingFile = current.drawingFile
            next.drawingFile = "drawings/\(next.id)-\(UUID()).drawing"
            try PageValidation.validate(next)
            entries.append(.init(expectedRevision: change.expectedRevision, page: next))
        }
        let journal = PageBatchJournal(documentID: manifest.documentID, notebookID: manifest.notebookID, entries: entries)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard try encoder.encode(journal).count <= 8 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        for i in changes.indices { try changes[i].drawing.write(to: url(entries[i].page.drawingFile!), options: .atomic) }
        try FileManager.default.createDirectory(at: url("recovery"), withIntermediateDirectories: true)
        try write(journal, PageBatchRecovery.path)
        markPendingPageBatch()
        try settlePageBatch()
        invalidateDerivedSearch()
        return entries.map(\.page)
    }
}
