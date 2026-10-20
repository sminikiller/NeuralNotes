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
        case .tooManyPages: return "Il PDF supera il limite di 1000 pagine per importazione. Dividilo in più quaderni."
        }
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
    static func importPDF(from url: URL, into workspace: DocumentWorkspace) async throws -> [PageSnapshot] {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try boundedRead(url)
        guard let pdf = PDFDocument(data: data) else { throw PDFImportFailure.unreadable }
        guard !pdf.isLocked else { throw PDFImportFailure.locked }
        guard pdf.pageCount > 0 else { throw PDFImportFailure.unreadable }
        guard pdf.pageCount <= 1000 else { throw PDFImportFailure.tooManyPages }
        let attachment = try await workspace.addAttachment(data, name: url.lastPathComponent, type: "pdf",
            hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        var result: [PageSnapshot] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let source = pdf.page(at: index), let reference = source.pageRef else { throw CocoaError(.fileReadCorruptFile) }
            let box = reference.getBoxRect(.cropBox)
            let rotated = abs(reference.rotationAngle) % 180 == 90
            var page = PageSnapshot()
            page.width = rotated ? box.height : box.width
            page.height = rotated ? box.width : box.height
            guard page.width > 0, page.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
            page.pdfFile = attachment.file; page.pdfIndex = index
            page.recognizedText = source.string ?? ""
            result.append(try await workspace.addPage(page))
        }
        return result
    }

    static func importImage(from url: URL, into workspace: DocumentWorkspace) async throws -> ImageElement {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try boundedRead(url)
        return try await importImage(data: data, into: workspace)
    }

    static func importImage(data: Data, into workspace: DocumentWorkspace) async throws -> ImageElement {
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary),
              let png = UIImage(cgImage: thumbnail).pngData() else { throw CocoaError(.fileReadCorruptFile) }
        let file = try await workspace.storeImage(png)
        let width = min(Double(thumbnail.width), 520)
        return ImageElement(file: file, width: width, height: width * Double(thumbnail.height) / Double(thumbnail.width))
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
            }
            await Task.yield()
        }
        try Task.checkCancellation()
        context.closePDF(); closed = true
        guard PDFDocument(url: output)?.pageCount == pages.count else { throw CocoaError(.fileWriteUnknown) }
        completed = true
        return output
    }

    static func boundedRead(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        return data
    }
}
