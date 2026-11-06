import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore

@MainActor enum LayerPDFExport {
    static func write(pages: [PageSnapshot], workspace: DocumentWorkspace, selection: LayerExportSelection, vectorInk: Bool) async throws -> URL {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-\(UUID()).pdf")
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        let archive = try PDFVectorArchive(url: output)
        for page in pages {
            try Task.checkCancellation(); try PageValidation.validate(page)
            let bounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            var forms: [Int] = []
            // Imported content is copied in a separate, unmodified scope. Never
            // relabel a source PDF's own transparency or embedded ICC profile.
            forms.append(try autoreleasepool {
                try form(archive: archive, bounds: bounds, owned: false) { context in
                    PageRenderer.drawPaper(page, package: workspace.package, in: context)
                }
            })
            for group in try LayerRenderPlan.make(page: page, selection: selection) where group.opacity > 0 {
                let drawing = try await LayerDrawingReader.read(page: page, layerID: group.layer.id, workspace: workspace).drawing
                try autoreleasepool {
                    let owner = PreparedLayerOwner(group: group, page: page, package: workspace.package, drawing: drawing,
                        bounds: bounds, scale: min(2, 4096 / max(bounds.width, bounds.height)), vector: vectorInk)
                    forms.append(try form(archive: archive, bounds: bounds, owned: true) { context in
                        LayerBlendCompositor.drawGroup(opacity: group.opacity, bounds: bounds, in: context, uniqueText: vectorInk) { owner.draw(in: $0) }
                    })
                }
                await Task.yield()
            }
            try archive.addPage(width: page.width, height: page.height, forms: forms)
            await Task.yield()
        }
        try archive.finish()
        guard PDFDocument(url: output)?.pageCount == pages.count else { throw CocoaError(.fileWriteUnknown) }
        completed = true; return output
    }
    private static func form(archive: PDFVectorArchive, bounds: CGRect, owned: Bool, draw: (CGContext) -> Void) throws -> Int {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NN-vector-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var media = bounds
        guard let consumer = CGDataConsumer(url: temporary as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.saveGState(); context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context); draw(context); UIGraphicsPopContext()
        context.restoreGState(); context.endPDFPage(); context.closePDF()
        guard let document = CGPDFDocument(temporary as CFURL), let page = document.page(at: 1) else { throw CocoaError(.fileWriteUnknown) }
        // Array/dictionary/stream references belong to their CGPDFDocument;
        // keep that container alive through every recursive resource copy,
        // including under Release's shorter ARC lifetimes.
        return try withExtendedLifetime(document) { try archive.pageForm(page, normalizeOwnedGroups: owned) }
    }
}
