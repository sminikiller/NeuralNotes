import Foundation

public extension DocumentWorkspace {
    static var maximumPageEditPages: Int { PageEditRecovery.maximumPages }
    /// Retained page headers let redo reuse a newly-created page after undo put
    /// it in the trash, without creating a second identity or losing its media.
    func retainedPageSnapshot(_ id: UUID) throws -> PageSnapshot? {
        _ = try manifest()
        guard FileManager.default.fileExists(atPath: try url("pages/\(id).json").path) else { return nil }
        return try readPage(id)
    }

    /// The snapshot is file-backed. Preparation keeps one page in memory and
    /// cancellation is allowed until publishing the recovery pointer. After
    /// that commit point, recovery finishes the edit before returning.
    func applyPageEdit(_ snapshot: PageEditSnapshot, expectedOrder: [UUID], newOrder: [UUID], expectedRevisions: [UUID: Int]) throws {
        let index = try manifest(), ids = Set(snapshot.pageIDs)
        guard snapshot.documentID == documentID, index.pageIDs == expectedOrder,
              (1...PageEditRecovery.maximumPages).contains(snapshot.pageIDs.count),
              !newOrder.isEmpty, newOrder.count <= PageEditRecovery.maximumPages,
              Set(newOrder).count == newOrder.count, Set(expectedRevisions.keys).isSubset(of: ids),
              ids.isSubset(of: Set(expectedOrder).union(newOrder)),
              Set(newOrder).subtracting(expectedOrder).isSubset(of: ids) else { throw WorkspaceFailure.staleRevision }
        // Check every expected revision before copying or publishing anything.
        for id in snapshot.pageIDs {
            try Task.checkCancellation()
            if let expected = expectedRevisions[id] {
                guard expected >= 0, expected < 1_000_000_000, try readPage(id).revision == expected else { throw WorkspaceFailure.staleRevision }
            } else {
                guard !FileManager.default.fileExists(atPath: try url("pages/\(id).json").path) else { throw WorkspaceFailure.staleRevision }
            }
            _ = try snapshot.page(id); _ = try snapshot.drawingURL(id)
        }
        let operation = UUID()
        let journal = PageEditJournal(operationID: operation, documentID: documentID, notebookID: index.notebookID,
            oldOrder: expectedOrder, newOrder: newOrder,
            entries: snapshot.pageIDs.map { .init(pageID: $0, expectedRevision: expectedRevisions[$0]) })
        let staging = try url(journal.directory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staging) } }
        try snapshot.restoreMedia(in: package)
        for id in snapshot.pageIDs {
            try Task.checkCancellation()
            let current = try expectedRevisions[id].map { _ in try readPage(id) }
            var next = try snapshot.page(id)
            next.revision = (expectedRevisions[id] ?? -1) + 1
            next.lastEditedAt = Date().timeIntervalSince1970
            if let ink = try snapshot.drawingURL(id) {
                let file = "drawings/\(id)-\(UUID()).drawing"
                try FileManager.default.copyItem(at: ink, to: url(file))
                next.drawingFile = file; next.previousDrawingFile = current?.drawingFile
            } else {
                next.drawingFile = current?.drawingFile; next.previousDrawingFile = current?.previousDrawingFile
            }
            try PageValidation.validate(next)
            for path in [next.drawingFile, next.previousDrawingFile, next.pdfFile].compactMap({ $0 }) + next.images.map(\.file) {
                guard try url(path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LibraryFailure.corruptDocument }
            }
            try write(next, journal.header(id))
        }
        try Task.checkCancellation()
        try write(journal, PageEditRecovery.path)
        published = true; markPendingPageBatch()
        try settlePageBatch(); invalidateDerivedSearch()
    }
}
