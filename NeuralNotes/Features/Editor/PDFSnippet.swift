import UIKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import NeuralNotesCore

struct PDFSnippetRequest: Sendable {
    let url: URL
    let index: Int
    let bounds: CGRect
    let pageSize: CGSize

    /// Convert PDFKit's page coordinates using the same crop/rotation transform
    /// as the notebook renderer. The region remains confined to the starting page.
    static func make(url: URL, index: Int, page: CGPDFPage, selection: CGRect) -> Self? {
        let crop = page.getBoxRect(.cropBox)
        let sideways = abs(page.rotationAngle) % 180 == 90
        let size = sideways ? CGSize(width: crop.height, height: crop.width) : crop.size
        guard index >= 0, size.width > 0, size.height > 0 else { return nil }
        let full = CGRect(origin: .zero, size: size)
        let transform = page.getDrawingTransform(.cropBox, rect: full, rotate: 0, preserveAspectRatio: true)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        let box = selection.standardized.applying(transform).intersection(full)
        guard !box.isNull, box.width >= 3, box.height >= 3,
              box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite else { return nil }
        return Self(url: url, index: index, bounds: box, pageSize: size)
    }
}

/// Owns the PDF decoder off the UI thread, never reads an entire file into Data.
actor PDFSnippetRenderer {
    static let shared = PDFSnippetRenderer()
    func render(_ request: PDFSnippetRequest) throws -> Data {
        let access = request.url.startAccessingSecurityScopedResource()
        defer { if access { request.url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        return try autoreleasepool {
            let full = CGRect(origin: .zero, size: request.pageSize)
            let box = request.bounds.intersection(full)
            guard !box.isNull, box.width >= 3, box.height >= 3,
                  box.width.isFinite, box.height.isFinite,
                  let pdf = CGPDFDocument(request.url as CFURL), pdf.isUnlocked,
                  request.index >= 0, request.index < pdf.numberOfPages,
                  let page = pdf.page(at: request.index + 1) else { throw PDFImportFailure.unreadable }
            let scale = min(2, 2048 / max(box.width, box.height))
            let width = max(1, Int(ceil(box.width * scale))), height = max(1, Int(ceil(box.height * scale)))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileReadTooLarge) }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.translateBy(x: 0, y: full.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: full, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            try Task.checkCancellation()
            guard let image = context.makeImage() else { throw PDFImportFailure.unreadable }
            let data = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw PDFImportFailure.unreadable }
            CGImageDestinationAddImage(output, image, nil)
            guard CGImageDestinationFinalize(output) else { throw PDFImportFailure.unreadable }
            return data as Data
        }
    }
}

@MainActor
final class PDFSnippetOverlay: UIView {
    weak var pdfView: ConceptPDFView?
    private var start = CGPoint.zero
    private weak var sourcePage: PDFPage?
    private let border = CAShapeLayer()
    init(pdfView: ConceptPDFView) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Seleziona un ritaglio del PDF"
        accessibilityHint = "Trascina dal primo all'ultimo angolo della zona da inserire nel foglio."
        accessibilityIdentifier = "studyPDFCropOverlay"
        border.fillColor = UIColor.systemTeal.withAlphaComponent(0.16).cgColor
        border.strokeColor = UIColor.systemTeal.cgColor; border.lineWidth = 2
        layer.addSublayer(border)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(nnSnippetDrag(_:)))
        pan.maximumNumberOfTouches = 1; addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { nil }
    func reset() { sourcePage = nil; border.path = nil }
    @objc private func nnSnippetDrag(_ gesture: UIPanGestureRecognizer) {
        guard let pdfView else { return }
        let point = gesture.location(in: pdfView)
        if gesture.state == .began {
            start = point; sourcePage = pdfView.page(for: point, nearest: false)
        }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        border.path = UIBezierPath(rect: rect).cgPath
        if gesture.state == .ended {
            defer { reset() }
            guard rect.width >= 8, rect.height >= 8, let sourcePage, let reference = sourcePage.pageRef,
                  let document = pdfView.document, let url = pdfView.snippetURL else { return }
            let index = document.index(for: sourcePage)
            guard index != NSNotFound, let request = PDFSnippetRequest.make(url: url, index: index,
                page: reference, selection: pdfView.convert(rect, to: sourcePage)) else { return }
            pdfView.snippetMode = false; pdfView.onSnippet?(request)
        } else if gesture.state == .cancelled || gesture.state == .failed { reset() }
    }
}

@MainActor
extension EditorViewModel {
    func insertPDFSnippet(_ request: PDFSnippetRequest) async throws {
        guard let destination = page?.id, hasLease, canEditActiveLayer, !interactionBusy, !navigating else { return }
        let owner = drawingLayerID
        let data = try await PDFSnippetRenderer.shared.render(request)
        try Task.checkCancellation()
        guard page?.id == destination, drawingLayerID == owner, hasLease, canEditActiveLayer, !interactionBusy, !navigating else {
            throw CocoaError(.userCancelled)
        }
        let element = try await DocumentServices.importImage(data: data, into: workspace)
        guard page?.id == destination, drawingLayerID == owner, hasLease, canEditActiveLayer, !interactionBusy, !navigating else {
            throw CocoaError(.userCancelled)
        }
        addImage(element)
    }
}
