import Foundation

public struct InspectedPackage: Sendable {
    public let manifest: DocumentManifest
    public let metadata: Notebook?
}

public enum NativePackageInspector {
    /// Validate before registering an imported package in the library. The source
    /// is read-only; decoding PencilKit/media payloads remains the platform's job.
    public static func inspect(_ package: URL) throws -> InspectedPackage {
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
            guard page.id == id, page.width.isFinite, page.height.isFinite,
                  page.width > 0, page.height > 0, page.width <= 20000, page.height <= 20000 else { throw LibraryFailure.corruptDocument }
            if let time = page.lastEditedAt, !time.isFinite || time < 0 { throw LibraryFailure.corruptDocument }
            for path in [page.drawingFile, page.previousDrawingFile, page.pdfFile].compactMap({ $0 }) + page.images.map(\.file) { try media(path) }
            guard (page.pdfMarkups ?? []).allSatisfy(\.isValid) else { throw LibraryFailure.corruptDocument }
            for text in page.texts {
                guard [text.x, text.y, text.width, text.fontSize].allSatisfy(\.isFinite),
                      text.width > 0, (1...1000).contains(text.fontSize) else { throw LibraryFailure.corruptDocument }
                if let rotation = text.rotation, !rotation.isFinite { throw LibraryFailure.corruptDocument }
                if let rtf = text.rtf, rtf.count > 2 * 1024 * 1024 { throw LibraryFailure.corruptDocument }
            }
            for image in page.images {
                guard [image.x, image.y, image.width, image.height].allSatisfy(\.isFinite),
                      image.width > 0, image.height > 0 else { throw LibraryFailure.corruptDocument }
                if let crop = image.crop {
                    guard [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite), crop.x >= 0, crop.y >= 0,
                          crop.width > 0, crop.height > 0, crop.x + crop.width <= 1.000001, crop.y + crop.height <= 1.000001 else { throw LibraryFailure.corruptDocument }
                }
                if let rotation = image.rotation, !rotation.isFinite { throw LibraryFailure.corruptDocument }
            }
            if let appearance = page.appearance, !appearance.isValid { throw LibraryFailure.corruptDocument }
            guard page.tapes?.allSatisfy(\.isValid) != false, page.texts.allSatisfy({ $0.background?.isValid != false }) else { throw LibraryFailure.corruptDocument }
            let objectIDs = Set(page.objectIDs)
            guard objectIDs.count == page.objectIDs.count else { throw LibraryFailure.corruptDocument }
            for references in [page.objectOrder, page.lockedObjects, page.aboveInkObjects].compactMap({ $0 }) {
                guard Set(references).count == references.count, Set(references).isSubset(of: objectIDs) else { throw LibraryFailure.corruptDocument }
            }
            for shape in page.shapes ?? [] {
                guard [shape.x, shape.y, shape.width, shape.height, shape.red, shape.green, shape.blue, shape.lineWidth].allSatisfy(\.isFinite),
                      shape.width > 0, shape.height > 0, (0...1).contains(shape.red), (0...1).contains(shape.green), (0...1).contains(shape.blue),
                      shape.lineWidth > 0, shape.lineWidth <= 200 else { throw LibraryFailure.corruptDocument }
                guard shape.start?.isValid ?? true, shape.end?.isValid ?? true else { throw LibraryFailure.corruptDocument }
                if let rotation = shape.rotation, !rotation.isFinite { throw LibraryFailure.corruptDocument }
            }
        }
        if FileManager.default.fileExists(atPath: package.appendingPathComponent("catalog.json").path) {
            let catalog: DocumentCatalog = try read("catalog.json")
            try CatalogRecovery.validateStudy(catalog)
            guard catalog.organization?.isValid != false else { throw LibraryFailure.corruptDocument }
            if let template = catalog.defaultPageTemplate, !template.appearance.isValid { throw LibraryFailure.corruptDocument }
            if let template = catalog.defaultPageTemplate, let file = template.pdfFile {
                try media(file)
                guard let index = template.pdfIndex, index >= 0, let width = template.sourceWidth, let height = template.sourceHeight,
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
