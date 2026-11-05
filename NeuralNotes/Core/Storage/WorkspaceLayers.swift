import Foundation

public extension DocumentWorkspace {
    /// Commit an entire layer header after every immutable media reference has
    /// been prepared. A crash sees the old header or the complete new one. The
    /// caller owns file-backed undo snapshots before any destructive operation.
    func saveLayerMetadata(_ input: PageSnapshot, expectedRevision: Int) throws -> PageSnapshot {
        let current = try pageSnapshot(input.id)
        guard expectedRevision >= 0, expectedRevision < 1_000_000_000,
              current.revision == expectedRevision, input.revision == expectedRevision else { throw WorkspaceFailure.staleRevision }
        try PageValidation.validate(input)
        for path in input.mediaFiles {
            let file = try url(path)
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true else { throw LibraryFailure.corruptDocument }
            if input.allDrawingFiles.contains(path), (info.fileSize ?? 0) > 100 << 20 { throw WorkspaceFailure.oversizedImport }
        }
        var page = input; page.revision += 1; page.lastEditedAt = Date().timeIntervalSince1970
        try write(page, "pages/\(page.id).json")
        // Do not keep one obsolete immutable file per slider/visibility edit.
        // The reachability index includes every other live or trashed owner.
        for old in Set(current.allDrawingFiles).subtracting(page.allDrawingFiles)
            where old.hasPrefix("drawings/\(page.id)-") && canReleaseDrawing(old) {
            try? FileManager.default.removeItem(at: url(old))
        }
        return page
    }
    /// Copy immutable bytes without loading PKDrawing into memory. Source
    /// metadata remains unchanged if preparation or the final header fails.
    func duplicateLayer(pageID: UUID, layerID: UUID, name: String) throws -> (page: PageSnapshot, layerID: UUID) {
        let result = try prepareLayerDuplicate(pageID: pageID, layerID: layerID, name: name)
        let saved = try saveLayerMetadata(result.page, expectedRevision: result.page.revision)
        return (saved, result.layerID)
    }
    /// Prepare immutable media without publishing the header. The editor uses
    /// this with its existing file-backed undo journal so duplication commits
    /// together with one chronological history entry. Abandoned media is
    /// unreachable and can be reclaimed by ordinary package maintenance.
    func prepareLayerDuplicate(pageID: UUID, layerID: UUID, name: String) throws -> (page: PageSnapshot, layerID: UUID) {
        let original = try pageSnapshot(pageID)
        let source = PageLayers.drawingFile(for: layerID, in: original)
        let copied = source.map { _ in "drawings/\(pageID)-\(UUID()).drawing" }
        let result = try PageLayerEditing.duplicating(layerID, in: original, name: name, drawingCopy: copied)
        if let source, let copied {
            let file = try url(source), info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, size <= 100 << 20 else { throw LibraryFailure.corruptDocument }
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: file, to: url(copied))
        }
        try Task.checkCancellation()
        return result
    }
}
