import Foundation

public struct WorkspaceStorageReport: Sendable {
    public var totalBytes: Int64
    public var unusedBytes: Int64
    public var unusedFiles: [String]
    public var removedPages: [PageSnapshot]
    public var unreadableHeaders: [String]
    public var categoryBytes: [String: Int64]
}

extension DocumentWorkspace {
    public func storageReport() throws -> WorkspaceStorageReport {
        let index = try manifest()
        let files = try PackageFiles.list(in: package)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var referenced = Set<String>(), removed: [PageSnapshot] = [], unreadable: [String] = []
        let names = Set(files.map(\.path))
        for id in index.pageIDs where !names.contains("pages/\(id).json") { unreadable.append("pages/\(id).json") }
        for file in files where file.path.hasPrefix("pages/") && file.url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file.url)
                let page = try decoder.decode(PageSnapshot.self, from: data)
                guard UUID(uuidString: file.url.deletingPathExtension().lastPathComponent) == page.id else { throw LibraryFailure.corruptDocument }
                for path in [page.drawingFile, page.previousDrawingFile, page.pdfFile].compactMap({ $0 }) + page.images.map(\.file) {
                    _ = try url(path); referenced.insert(path)
                }
                if !index.pageIDs.contains(page.id) { removed.append(page) }
            } catch { unreadable.append(file.path) }
        }
        do {
            let catalog = try catalog()
            for path in catalog.attachments.map(\.file) + catalog.sessions.flatMap({ $0.segments.map(\.file) }) + [catalog.coverImageFile].compactMap({ $0 }) {
                _ = try url(path); referenced.insert(path)
            }
        } catch { unreadable.append("catalog.json") }
        if names.contains(CatalogRecovery.previousPath) {
            do {
                let previous = try CatalogRecovery.read(CatalogRecovery.previousPath, package: package)
                for path in CatalogRecovery.references(previous) { referenced.insert(path) }
            } catch { unreadable.append(CatalogRecovery.previousPath) }
        }
        do { referenced.formUnion(try CatalogRecovery.retainedMedia(in: package)) }
        catch { unreadable.append(CatalogRecovery.retainedPath) }
        do {
            if let pending = try pendingAudioCompression() {
                referenced.formUnion(pending.parts.flatMap { [$0.source, $0.destination] })
            }
        } catch { unreadable.append(AudioCompressionPlan.path) }
        var total: Int64 = 0, unused: Int64 = 0, unusedFiles: [String] = [], categories: [String: Int64] = [:]
        for file in files {
            let size = Int64(try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            let category = String(file.path.split(separator: "/").first ?? "metadata")
            total += size; categories[category, default: 0] += size
            if ["drawings", "images", "audio", "attachments"].contains(category), !referenced.contains(file.path) {
                unused += size; unusedFiles.append(file.path)
            }
        }
        return WorkspaceStorageReport(totalBytes: total, unusedBytes: unused, unusedFiles: unusedFiles,
            removedPages: removed.sorted { $0.id.uuidString < $1.id.uuidString }, unreadableHeaders: unreadable, categoryBytes: categories)
    }

    /// Recompute reachability inside the actor immediately before deletion. Both
    /// active and removed page headers protect their current and previous media.
    public func cleanUnusedFiles() throws -> Int64 {
        guard try pendingAudioCompression() == nil else { throw LibraryFailure.recoveryRequired("Riprendi prima la compressione audio.") }
        let report = try storageReport()
        guard report.unreadableHeaders.isEmpty else {
            throw LibraryFailure.recoveryRequired("Un indice non è leggibile. Pulizia annullata per conservare i contenuti.")
        }
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else {
            throw LibraryFailure.recoveryRequired("Metti in pausa l’audio prima della pulizia.")
        }
        for path in report.unusedFiles { try FileManager.default.removeItem(at: url(path)) }
        return report.unusedBytes
    }

    public func restoreRemovedPage(_ id: UUID) throws {
        let index = try manifest()
        guard !index.pageIDs.contains(id) else { return }
        try restorePageOrder(index.pageIDs + [id], expected: index.pageIDs)
    }

    public func permanentlyRemovePages(_ ids: [UUID]) throws {
        let index = try manifest()
        guard Set(ids).isDisjoint(with: index.pageIDs) else { throw WorkspaceFailure.staleRevision }
        guard try storageReport().unreadableHeaders.isEmpty else { throw LibraryFailure.corruptDocument }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: url("manifest.previous.json"), options: .atomic)
        for id in ids {
            let file = try url("pages/\(id).json")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
}
