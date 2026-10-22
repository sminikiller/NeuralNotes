import UIKit
import PDFKit
import PencilKit
import CryptoKit
import ImageIO
import NeuralNotesCore

enum PDFImportFailure: LocalizedError {
    case unreadable, locked, tooManyPages
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Il PDF non è leggibile o non contiene pagine valide. Il file originale è stato conservato."
        case .locked: return "Il PDF è protetto da password. Sbloccalo prima di importarlo. Il file originale è stato conservato."
        case .tooManyPages: return "Il PDF supera il limite di \(PDFImportPolicy.maximumPages) pagine per importazione. Dividilo in più quaderni."
        }
    }
}

/// Reuse a file-backed PDF while indexing nearby pages, then release its page
/// objects periodically. Only strings cross the actor boundary.
actor PDFTextReader {
    static let shared = PDFTextReader()
    private var file: URL?
    private var document: PDFDocument?
    private var reads = 0
    func text(url: URL, index: Int) throws -> String {
        try Task.checkCancellation()
        if file != url || document == nil || reads >= 32 {
            document = nil; file = url; reads = 0
            document = PDFDocument(url: url)
        }
        guard let document, !document.isLocked, index >= 0, index < document.pageCount else { throw PDFImportFailure.unreadable }
        reads += 1
        return autoreleasepool { String((document.page(at: index)?.string ?? "").prefix(20_000)) }
    }
    /// Digital text inside an area of a notebook page made from a PDF page. Notebook
    /// coordinates grow downward from the top, PDF coordinates upward from the bottom.
    func text(url: URL, index: Int, in area: CGRect, pageWidth: Double, pageHeight: Double) throws -> String {
        try Task.checkCancellation()
        if file != url || document == nil || reads >= 32 {
            document = nil; file = url; reads = 0
            document = PDFDocument(url: url)
        }
        guard let document, !document.isLocked, index >= 0, index < document.pageCount, let page = document.page(at: index),
              pageWidth > 0, pageHeight > 0, page.rotation == 0 else { return "" }
        reads += 1
        let box = page.bounds(for: .cropBox)
        let sx = box.width / CGFloat(pageWidth), sy = box.height / CGFloat(pageHeight)
        let rect = CGRect(x: box.minX + area.minX * sx, y: box.minY + (CGFloat(pageHeight) - area.maxY) * sy,
                          width: area.width * sx, height: area.height * sy)
        return autoreleasepool { String((page.selection(for: rect)?.string ?? "").prefix(6000)) }
    }
}

@MainActor
enum DocumentServices {
    static func photoPreview(_ data: Data) throws -> UIImage {
        guard data.count <= 100 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: image)
    }
    static func importPDF(from url: URL, into workspace: DocumentWorkspace,
                          progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws -> [PageSnapshot] {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NN-PDF-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        progress("Preparazione PDF…")
        let job = Task.detached(priority: .userInitiated) {
            try CoordinatedFileAccess.read(url) { source in
                let staged = try PDFFileImport.stage(from: source, to: temporary) { copied, total in
                    let percent = copied * 100 / max(1, total)
                    Task { @MainActor in progress("Copia PDF · \(percent)%") }
                }
                return try preparePDF(staged)
            }
        }
        let prepared = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try Task.checkCancellation()
        progress("Salvataggio di \(prepared.pages.count) pagine…")
        return try await workspace.installPDF(prepared.file, name: url.lastPathComponent, pages: prepared.pages)
    }

    static func importImage(from url: URL, into workspace: DocumentWorkspace) async throws -> ImageElement {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let job = Task.detached(priority: .userInitiated) { try boundedRead(url) }
        let data = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        return try await importImage(data: data, into: workspace)
    }

    static func importImage(data: Data, into workspace: DocumentWorkspace) async throws -> ImageElement {
        let job = Task.detached(priority: .userInitiated) { try prepareImage(data) }
        let prepared = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try Task.checkCancellation()
        let file = try await workspace.storeImage(prepared.data)
        let width = min(Double(prepared.width), 520)
        return ImageElement(file: file, width: width, height: width * Double(prepared.height) / Double(prepared.width))
    }

    private struct PreparedPDF: Sendable { let file: StagedPDFFile; let pages: [PageSnapshot] }
    nonisolated private static func preparePDF(_ file: StagedPDFFile) throws -> PreparedPDF {
        guard let pdf = CGPDFDocument(file.url as CFURL) else { throw PDFImportFailure.unreadable }
        guard pdf.isUnlocked else { throw PDFImportFailure.locked }
        guard pdf.numberOfPages > 0 else { throw PDFImportFailure.unreadable }
        guard pdf.numberOfPages <= PDFImportPolicy.maximumPages else { throw PDFImportFailure.tooManyPages }
        // Large PDFs need only their geometry at import. Text extraction is
        // available on demand and through the resumable library indexer.
        let textPDF = pdf.numberOfPages <= PDFImportPolicy.eagerTextPageLimit ? PDFDocument(url: file.url) : nil
        var pages: [PageSnapshot] = []
        for index in 0..<pdf.numberOfPages {
            try Task.checkCancellation()
            let page: PageSnapshot = try autoreleasepool {
                guard let reference = pdf.page(at: index + 1) else { throw PDFImportFailure.unreadable }
                let box = reference.getBoxRect(.cropBox), rotated = abs(reference.rotationAngle) % 180 == 90
                var page = PageSnapshot()
                page.width = rotated ? box.height : box.width; page.height = rotated ? box.width : box.height
                guard page.width.isFinite, page.height.isFinite, (1...20000).contains(page.width), (1...20000).contains(page.height) else { throw PDFImportFailure.unreadable }
                page.pdfIndex = index; page.recognizedText = String((textPDF?.page(at: index)?.string ?? "").prefix(20000))
                return page
            }
            pages.append(page)
        }
        return PreparedPDF(file: file, pages: pages)
    }
    static func pdfText(page: PageSnapshot, workspace: DocumentWorkspace) async throws -> String {
        guard let file = page.pdfFile, let index = page.pdfIndex else { return "" }
        let url = try await workspace.url(file)
        let text = try await PDFTextReader.shared.text(url: url, index: index)
        try Task.checkCancellation()
        return text
    }
    private struct PreparedImage: Sendable { let data: Data; let width: Int; let height: Int }
    nonisolated private static func prepareImage(_ data: Data) throws -> PreparedImage {
        try Task.checkCancellation()
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try Task.checkCancellation()
        return PreparedImage(data: output as Data, width: thumbnail.width, height: thumbnail.height)
    }

    static func importAttachment(from url: URL, into workspace: DocumentWorkspace) async throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try boundedRead(url)
        _ = try await workspace.addAttachment(data, name: url.lastPathComponent, type: url.pathExtension,
            hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    static func image(page: PageSnapshot, drawing: PKDrawing, workspace: DocumentWorkspace, maxDimension: CGFloat = 2048) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, maxDimension / max(bounds.width, bounds.height))
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { result in
            PageRenderer.draw(page, package: workspace.package, in: result.cgContext)
            PaperInk.image(drawing, from: bounds, scale: format.scale).draw(in: bounds)
            PageRenderer.drawForeground(page, package: workspace.package, in: result.cgContext)
        }
    }

    static func exportPDF(workspace: DocumentWorkspace, vectorInk: Bool = true) async throws -> URL {
        let pages = try await workspace.pages()
        guard !pages.isEmpty else { throw WorkspaceFailure.emptyDocument }
        // Load each drawing only as its page is emitted; never rasterize an entire notebook.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-\(UUID()).pdf")
        var bounds = CGRect(x: 0, y: 0, width: pages[0].width, height: pages[0].height)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            try? FileManager.default.removeItem(at: output); throw CocoaError(.fileWriteUnknown)
        }
        var completed = false, closed = false
        defer {
            if !closed { context.closePDF() }
            if !completed { try? FileManager.default.removeItem(at: output) }
        }
        for page in pages {
            try Task.checkCancellation()
            let file: URL?
            if let relative = page.drawingFile { file = try await workspace.url(relative) } else { file = nil }
            // No UIKit current context is kept across suspension points. A page
            // is completed synchronously, then the main actor can service input.
            try autoreleasepool {
                var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
                let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
                context.saveGState()
                context.translateBy(x: 0, y: box.height); context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                defer { UIGraphicsPopContext(); context.restoreGState(); context.endPDFPage() }
                PageRenderer.draw(page, package: workspace.package, in: context)
                if let file {
                    let drawing = try PKDrawing(data: Data(contentsOf: file))
                    if vectorInk { VectorInkRenderer.draw(drawing, in: context) }
                    else { PaperInk.image(drawing, from: box, scale: min(2, 4096 / max(box.width, box.height))).draw(in: box) }
                }
                PageRenderer.drawForeground(page, package: workspace.package, in: context)
            }
            await Task.yield()
        }
        try Task.checkCancellation()
        context.closePDF(); closed = true
        guard PDFDocument(url: output)?.pageCount == pages.count else { throw CocoaError(.fileWriteUnknown) }
        completed = true
        return output
    }

    nonisolated static func boundedRead(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        return data
    }
}
