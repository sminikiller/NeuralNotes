import UIKit
import CoreGraphics
import NeuralNotesCore

/// Immutable source PDFs are shared by paper rendering; images are bounded by cost.
@MainActor
final class DocumentRenderCache {
    static let shared = DocumentRenderCache()
    private let pdfs = NSCache<NSURL, PDFBox>()
    private let images = NSCache<NSURL, UIImage>()
    private let crops = NSCache<NSString, UIImage>()
    private(set) var pdfOpens = 0
    init() { pdfs.countLimit = 6; images.totalCostLimit = 32 * 1024 * 1024; crops.totalCostLimit = 64 * 1024 * 1024; crops.countLimit = 12 }
    private final class PDFBox { let value: CGPDFDocument; init(_ value: CGPDFDocument) { self.value = value } }
    func pdf(_ url: URL) -> CGPDFDocument? {
        if let cached = pdfs.object(forKey: url as NSURL) { return cached.value }
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        pdfOpens += 1; pdfs.setObject(PDFBox(document), forKey: url as NSURL); return document
    }
    func image(_ url: URL) -> UIImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        images.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.scale * image.size.height * image.scale) * 4)
        return image
    }
    func croppedImage(_ url: URL, crop: NormalizedCrop, perspective: PerspectiveQuad? = nil, quarterTurns: Int = 0, enhanced: Bool = false) -> UIImage? {
        guard let image = image(url) else { return nil }
        if crop == .full, perspective == nil, quarterTurns == 0, !enhanced, image.imageOrientation == .up { return image }
        let edit = PhotoAdjustment(crop: crop, perspective: perspective, quarterTurns: quarterTurns, enhanced: enhanced)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(edit) else { return nil }
        let key = "\(url.path)|\(encoded.base64EncodedString())" as NSString
        if let cached = crops.object(forKey: key) { return cached }
        guard let value = PhotoPerspective.render(image, adjustment: edit), let cut = value.cgImage else { return nil }
        crops.setObject(value, forKey: key, cost: cut.width * cut.height * 4)
        return value
    }
    func clear() { pdfs.removeAllObjects(); images.removeAllObjects(); crops.removeAllObjects() }
}
