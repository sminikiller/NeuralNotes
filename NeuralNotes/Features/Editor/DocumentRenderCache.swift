import UIKit
import CoreGraphics

/// Immutable source PDFs are shared by paper rendering; images are bounded by cost.
@MainActor
final class DocumentRenderCache {
    static let shared = DocumentRenderCache()
    private let pdfs = NSCache<NSURL, PDFBox>()
    private let images = NSCache<NSURL, UIImage>()
    private(set) var pdfOpens = 0
    init() { pdfs.countLimit = 6; images.totalCostLimit = 32 * 1024 * 1024 }
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
    func clear() { pdfs.removeAllObjects(); images.removeAllObjects() }
}
