import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

public enum PDFImportPolicy {
    public static let maximumBytes: Int64 = 1 << 30
    public static let maximumPages = 5000
    public static let chunkBytes = 1 << 20
    public static let eagerTextPageLimit = 200
    public static func requiredFreeBytes(for bytes: Int64) -> Int64 { max(0, min(maximumBytes, bytes)) + (64 << 20) }
}
public enum PDFFileImportFailure: Error, LocalizedError {
    case tooLarge, noSpace, invalidFile, changed
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Il PDF supera il limite di 1 GB per file. Il file originale è stato conservato."
        case .noSpace: return "Spazio insufficiente per copiare il PDF. Libera spazio e riprova; il file originale è stato conservato."
        case .invalidFile: return "Il file non è un PDF leggibile. Il file originale è stato conservato."
        case .changed: return "Il PDF è cambiato durante la lettura. Attendi il download completo in File e riprova."
        }
    }
}
public struct StagedPDFFile: Sendable {
    public let url: URL
    public let bytes: Int64
    public let sha256: String
    let modifiedAt: Date?
}

/// Copies once, hashes incrementally, and retains at most a 1 MiB input chunk.
/// PDF structure is validated by PDFKit/Core Graphics before installation.
public enum PDFFileImport {
    public static func stage(from source: URL, to destination: URL,
                             availableBytes: Int64? = nil,
                             progress: @Sendable (Int64, Int64) -> Void = { _, _ in }) throws -> StagedPDFFile {
        try Task.checkCancellation()
        guard source.isFileURL, destination.isFileURL, source.standardizedFileURL != destination.standardizedFileURL else { throw PDFFileImportFailure.invalidFile }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PDFFileImportFailure.invalidFile }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else { throw PDFFileImportFailure.invalidFile }
        guard size <= PDFImportPolicy.maximumBytes else { throw PDFFileImportFailure.tooLarge }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let parent = destination.deletingLastPathComponent()
        let free = try availableBytes ?? (FileManager.default.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= PDFImportPolicy.requiredFreeBytes(for: size) else { throw PDFFileImportFailure.noSpace }
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let prefix = try input.read(upToCount: 1024) ?? Data()
        guard prefix.range(of: Data("%PDF-".utf8)) != nil else { throw PDFFileImportFailure.invalidFile }
        try input.seek(toOffset: 0)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: destination) } }
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        var hasher = SHA256(), copied: Int64 = 0, reported: Int64 = 0
        let interval = max(Int64(PDFImportPolicy.chunkBytes), size / 100)
        progress(0, size)
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: PDFImportPolicy.chunkBytes) ?? Data()
            if data.isEmpty { break }
            guard Int64(data.count) <= size - copied else { throw PDFFileImportFailure.changed }
            try output.write(contentsOf: data); hasher.update(data: data); copied += Int64(data.count)
            if copied - reported >= interval || copied == size { progress(copied, size); reported = copied }
        }
        try Task.checkCancellation()
        let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard copied == size, after.fileSize == values.fileSize, after.contentModificationDate == values.contentModificationDate else { throw PDFFileImportFailure.changed }
        try output.synchronize(); try output.close()
        let modifiedAt = try destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        completed = true
        return StagedPDFFile(url: destination, bytes: size, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(), modifiedAt: modifiedAt)
    }
}

public extension DocumentWorkspace {
    /// Metadata is published only after the complete source and all page headers
    /// exist. The staged file is moved, avoiding a second full-size byte copy.
    func installPDF(_ staged: StagedPDFFile, name: String, pages inputs: [PageSnapshot]) throws -> [PageSnapshot] {
        try Task.checkCancellation()
        guard (1...PDFImportPolicy.maximumPages).contains(inputs.count), staged.bytes > 0,
              staged.bytes <= PDFImportPolicy.maximumBytes, staged.sha256.count == 64 else { throw PDFFileImportFailure.invalidFile }
        let values = try staged.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == staged.bytes, values.contentModificationDate == staged.modifiedAt else { throw PDFFileImportFailure.changed }
        let existing = try manifest(), originalCatalog = try catalog()
        var ids = Set(existing.pageIDs)
        let attachment = Attachment(file: "attachments/\(UUID()).pdf", originalName: name, type: "pdf", sha256: staged.sha256)
        var pages = inputs
        for i in pages.indices {
            guard ids.insert(pages[i].id).inserted, pages[i].pdfIndex == i,
                  !FileManager.default.fileExists(atPath: try url("pages/\(pages[i].id).json").path),
                  pages[i].drawingFile == nil, pages[i].previousDrawingFile == nil,
                  pages[i].texts.isEmpty, pages[i].anchors.isEmpty, pages[i].images.isEmpty else { throw PDFFileImportFailure.invalidFile }
            pages[i].pdfFile = attachment.file
            try PageValidation.validate(pages[i])
        }
        let destination = try url(attachment.file)
        try FileManager.default.moveItem(at: staged.url, to: destination)
        do {
            var catalog = originalCatalog; catalog.attachments.append(attachment)
            try write(catalog, "catalog.json")
            let result = try appendPages(pages)
            invalidateDerivedSearch()
            return result
        } catch {
            // Never remove assets when a manifest may already reference them.
            if let live = try? manifest(), Set(live.pageIDs).isDisjoint(with: Set(pages.map(\.id))) {
                // Do not rotate catalog.previous to a failed import's catalog.
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
                if let bytes = try? encoder.encode(originalCatalog) { try? bytes.write(to: url("catalog.json"), options: .atomic) }
                invalidateDerivedSearch()
                if let catalog = try? catalog(), !catalog.attachments.contains(where: { $0.id == attachment.id }) { try? FileManager.default.removeItem(at: destination) }
                for page in pages { if let file = try? url("pages/\(page.id).json") { try? FileManager.default.removeItem(at: file) } }
            }
            throw error
        }
    }
}
