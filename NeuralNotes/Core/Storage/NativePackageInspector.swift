import Foundation

public struct InspectedPackage: Sendable {
    public let manifest: DocumentManifest
    public let metadata: Notebook?
}

public enum NativePackageInspector {
    /// Validate before registering an imported package in the library. The source
    /// is read-only; decoding PencilKit/media payloads remains the platform's job.
    public static func inspect(_ package: URL, allowInterruptedAudio: Bool = false) throws -> InspectedPackage {
        if !allowInterruptedAudio && FileManager.default.fileExists(atPath: package.appendingPathComponent(AudioCompressionPlan.path).path) {
            throw LibraryFailure.recoveryRequired("Riprendi la compressione audio nell’app prima di esportare o copiare il quaderno.")
        }
        if FileManager.default.fileExists(atPath: package.appendingPathComponent(PageBatchRecovery.path).path) {
            throw LibraryFailure.recoveryRequired("Completa il recupero del quaderno nell’app prima di esportarlo o copiarlo.")
        }
        guard let iterator = FileManager.default.enumerator(at: package,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else {
            throw LibraryFailure.corruptDocument
        }
        var total: UInt64 = 0, count = 0
        for case let file as URL in iterator {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw WorkspaceFailure.invalidPath }
            count += 1; total += UInt64(max(0, values.fileSize ?? 0))
            guard count <= 50_000, total <= 16 * 1024 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
            if file.pathExtension == "json", (values.fileSize ?? 0) > 16 * 1024 * 1024 { throw NativeArchiveFailure.limit }
            if ["drawing", "png"].contains(file.pathExtension), (values.fileSize ?? 0) > 100 * 1024 * 1024 { throw NativeArchiveFailure.limit }
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        func read<T: Decodable>(_ path: String) throws -> T {
            let url = try NativeArchive.fileURL(path, in: package)
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else {
                throw NativeArchiveFailure.limit
            }
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        }
        func media(_ path: String) throws {
            let url = try NativeArchive.fileURL(path, in: package)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw LibraryFailure.corruptDocument
            }
        }
        let manifest: DocumentManifest = try read("manifest.json")
        guard manifest.schemaVersion == 1 else { throw LibraryFailure.unsupportedVersion(manifest.schemaVersion) }
        guard Set(manifest.pageIDs).count == manifest.pageIDs.count else { throw LibraryFailure.corruptDocument }
        for id in manifest.pageIDs {
            let page: PageSnapshot = try read("pages/\(id).json")
            guard page.id == id else { throw LibraryFailure.corruptDocument }
            try PageValidation.validate(page)
            for path in [page.drawingFile, page.previousDrawingFile, page.pdfFile].compactMap({ $0 }) + page.images.map(\.file) { try media(path) }
        }
        if FileManager.default.fileExists(atPath: package.appendingPathComponent("catalog.json").path) {
            let catalog: DocumentCatalog = try read("catalog.json")
            try CatalogRecovery.validateStudy(catalog)
            guard catalog.organization?.isValid != false else { throw LibraryFailure.corruptDocument }
            if let template = catalog.defaultPageTemplate, !template.appearance.isValid { throw LibraryFailure.corruptDocument }
            if let template = catalog.defaultPageTemplate, let file = template.pdfFile {
                try media(file)
                guard let index = template.pdfIndex, index >= 0, index < Int.max, let width = template.sourceWidth, let height = template.sourceHeight,
                      width.isFinite, height.isFinite, (1...20000).contains(width), (1...20000).contains(height) else { throw LibraryFailure.corruptDocument }
            }
            if let settings = catalog.editorWorkspaces, !settings.isValid { throw LibraryFailure.corruptDocument }
            if let design = catalog.coverDesign, !design.isValid { throw LibraryFailure.corruptDocument }
            guard catalog.schemaVersion == 1, Set(catalog.sessions.map(\.id)).count == catalog.sessions.count else {
                throw LibraryFailure.corruptDocument
            }
            if let cover = catalog.coverImageFile { try media(cover) }
            for attachment in catalog.attachments { try media(attachment.file) }
            for session in catalog.sessions {
                let bookmarks = session.bookmarks ?? []
                guard bookmarks.count <= 1000, Set(bookmarks.map(\.id)).count == bookmarks.count,
                      bookmarks.allSatisfy({ $0.isValid && $0.seconds <= session.duration + 1 }) else { throw LibraryFailure.corruptDocument }
                for chunk in session.transcriptionChunks ?? [] {
                    guard chunk.window.start.isFinite, chunk.window.duration.isFinite, chunk.window.start >= 0,
                          chunk.window.duration > 0, chunk.window.duration <= 60,
                          session.segments.contains(where: { $0.file == chunk.file }) else { throw LibraryFailure.corruptDocument }
                }
                for correction in session.transcriptCorrections ?? [] {
                    guard correction.start.isFinite, correction.start >= 0 else { throw LibraryFailure.corruptDocument }
                }
                for segment in session.segments {
                    guard segment.codec == nil || (segment.codec == "aac" && segment.bitRate == 64_000 && segment.file.hasSuffix(".m4a") && (segment.originalBytes ?? 0) > 0) else { throw LibraryFailure.corruptDocument }
                    guard segment.start.isFinite, segment.duration.isFinite, segment.start >= 0, segment.duration >= 0 else {
                        throw LibraryFailure.corruptDocument
                    }
                    try media(segment.file)
                }
            }
        }
        let metadata: Notebook?
        if FileManager.default.fileExists(atPath: package.appendingPathComponent("metadata.json").path) {
            metadata = try read("metadata.json")
            guard metadata?.documentID == manifest.documentID, metadata?.id == manifest.notebookID else { throw LibraryFailure.corruptDocument }
        } else { metadata = nil }
        return InspectedPackage(manifest: manifest, metadata: metadata)
    }
}
