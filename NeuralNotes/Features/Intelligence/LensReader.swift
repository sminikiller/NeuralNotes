import UIKit
import NeuralNotesCore

/// What the Lens reads from a selection: digital PDF text when the page comes from
/// a PDF, typed text boxes, and OCR of the drawn page as the last resort.
@MainActor
enum LensReader {
    static func text(in area: CGRect, model: EditorViewModel) async -> String {
        guard let page = model.page else { return "" }
        var parts: [String] = []
        for text in page.texts where RichText.bounds(text, pageHeight: page.height).intersects(area) { parts.append(text.text) }
        if let file = page.pdfFile, let index = page.pdfIndex, let url = try? await model.workspace.url(file),
           let digital = try? await PDFTextReader.shared.text(url: url, index: index, in: area, pageWidth: page.width, pageHeight: page.height),
           !digital.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(digital)
        }
        if parts.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let crop = crop(area, model: model, maxDimension: 1600),
           let png = crop.pngData() {
            parts.append(await ocr(png))
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text of the whole page, used only to choose the meaning of an underlined term.
    static func pageText(model: EditorViewModel) async -> String {
        guard let page = model.page else { return "" }
        var text = page.texts.map(\.text).joined(separator: "\n") + "\n" + page.recognizedText
        if page.pdfFile != nil, let pdf = try? await DocumentServices.pdfText(page: page, workspace: model.workspace) { text = pdf + "\n" + text }
        return text
    }

    static func ocr(_ data: Data) async -> String {
        ((try? await VisionOCRService().recognize(image: data)) ?? []).map(\.text).joined(separator: "\n")
    }

    /// The drawn page inside an area, ink and objects included.
    static func crop(_ area: CGRect, model: EditorViewModel, maxDimension: CGFloat) -> UIImage? {
        guard let page = model.page else { return nil }
        let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: maxDimension)
        let box = area.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        guard !box.isNull, box.width > 3, box.height > 3 else { return nil }
        let pixels = CGRect(x: box.minX * image.scale, y: box.minY * image.scale, width: box.width * image.scale, height: box.height * image.scale)
        return image.cgImage?.cropping(to: pixels).map { UIImage(cgImage: $0) }
    }

    /// An image element of the page, as stored in the notebook.
    static func picture(_ id: UUID, model: EditorViewModel) async -> UIImage? {
        guard let element = model.page?.images.first(where: { $0.id == id }), let url = try? await model.workspace.url(element.file),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? DocumentServices.photoPreview(data)
    }

    /// A JPEG small enough for every provider (at most 1024 px per side), as base64.
    static func jpegBase64(_ image: UIImage, maxDimension: CGFloat = 1024) -> String? {
        let side = max(image.size.width * image.scale, image.size.height * image.scale)
        guard side > 0 else { return nil }
        let factor = min(1, maxDimension / side)
        let size = CGSize(width: max(1, (image.size.width * image.scale * factor).rounded()), height: max(1, (image.size.height * image.scale * factor).rounded()))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
