import UIKit
import PencilKit
import NeuralNotesCore

/// Only one owner's native archive is decoded at a time. Bitmap and PDF
/// exports share the same owner order, internal stages and group composition.
/// A live owner override includes unsaved ink without writing another owner.
@MainActor
enum LayeredPageRenderer {
    static func image(page: PageSnapshot, workspace: DocumentWorkspace, maxDimension: CGFloat = 2048,
                      selection: LayerExportSelection = .visible, liveDrawing: PKDrawing? = nil,
                      liveLayerID: UUID? = nil, pdfMode: PDFRenderMode = .vector) async throws -> UIImage {
        try PageValidation.validate(page)
        let bounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        guard maxDimension.isFinite, maxDimension > 0 else { throw WorkspaceFailure.oversizedImport }
        let scale = min(2, maxDimension / max(bounds.width, bounds.height))
        let width = Int(ceil(bounds.width * scale)), height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 32_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw WorkspaceFailure.oversizedImport
        }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        try await draw(page: page, workspace: workspace, in: context, bounds: bounds, scale: scale,
            selection: selection, liveDrawing: liveDrawing, liveLayerID: liveLayerID, pdfMode: pdfMode)
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    static func draw(page: PageSnapshot, workspace: DocumentWorkspace, in context: CGContext,
                     bounds: CGRect, scale: CGFloat, selection: LayerExportSelection = .visible,
                     liveDrawing: PKDrawing? = nil, liveLayerID: UUID? = nil,
                     vector: Bool = false, pdfMode: PDFRenderMode = .vector) async throws {
        let plan = try LayerRenderPlan.make(page: page, selection: selection)
        // Never retain UIGraphics' thread-local context across an await.
        withContext(context) { PageRenderer.drawPaper(page, package: workspace.package, in: context, pdfMode: pdfMode) }
        for group in plan where group.opacity > 0 {
            try Task.checkCancellation()
            let drawing: PKDrawing
            if group.layer.id == liveLayerID, let liveDrawing { drawing = liveDrawing }
            else { drawing = try await LayerDrawingReader.read(page: page, layerID: group.layer.id, workspace: workspace).drawing }
            autoreleasepool {
                withContext(context) {
                    let owner = PreparedLayerOwner(group: group, page: page, package: workspace.package, drawing: drawing,
                        bounds: bounds, scale: scale, vector: vector)
                    LayerBlendCompositor.drawGroup(opacity: group.opacity, bounds: bounds, in: context, uniqueText: vector) { owner.draw(in: $0) }
                }
            }
            await Task.yield()
        }
    }

    private static func withContext(_ context: CGContext, _ body: () -> Void) {
        UIGraphicsPushContext(context); defer { UIGraphicsPopContext() }
        body()
    }
}
