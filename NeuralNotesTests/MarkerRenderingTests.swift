import XCTest
import UIKit
import PDFKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class MarkerRenderingTests: XCTestCase {
    @MainActor private func ink(_ type: PKInkingTool.InkType, color: UIColor, y: CGFloat, width: CGFloat) -> PKStroke {
        let samples = [CGPoint(x: 40, y: y), CGPoint(x: 240, y: y)].enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i) * 0.1, size: .init(width: width, height: width),
                opacity: type == .marker ? 0.4 : 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(type, color: color), path: PKStrokePath(controlPoints: samples, creationDate: Date()))
    }
    @MainActor func testMarkerCompositionReusesTheDocumentAcrossPointerSamplesAndKeepsWhitePenAboveColor() throws {
        var page = PageSnapshot(); page.width = 300; page.height = 200; page.appearance = .init(tone: .slate)
        let base = PKDrawing(strokes: [ink(.pen, color: .white, y: 70, width: 4)])
        let cache = MarkerCompositionCache(), token = UUID(), bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        var last = UIImage()
        for _ in 0..<12 {
            let delta = PKDrawing(strokes: [ink(.marker, color: .yellow, y: 70, width: 24)])
            last = renderer.image { item in
                cache.draw(page: page, baseline: base, token: token, delta: delta, package: URL(fileURLWithPath: "/"),
                    bounds: bounds, scale: 2, hiddenIDs: [], hiddenTextID: nil, in: item.cgContext)
            }
        }
        XCTAssertEqual(cache.builds, 1, "La pagina non si deve ridisegnare a ogni campione della penna.")
        let image = try XCTUnwrap(last.cgImage), strip = try XCTUnwrap(image.cropping(to: CGRect(x: 50, y: 67, width: 180, height: 6).applying(.init(scaleX: CGFloat(image.width) / 300, y: CGFloat(image.height) / 200))))
        XCTAssertGreaterThan(pixelCount(strip, white: true), 80, "Il colore deve restare sotto l’inchiostro bianco sulla carta scura.")
        cache.clear()
    }
    @MainActor func testDigitalWordBoxesMatchRenderedGlyphsInRotatedPDFPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let bytes = UIGraphicsPDFRenderer(bounds: .init(x: 0, y: 0, width: 600, height: 800)).pdfData { renderer in
            renderer.beginPage(); ("Energia" as NSString).draw(at: .init(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
        }
        for rotation in [0, 90, 180, 270] {
            let path = "attachments/rotated-\(rotation).pdf", url = try await workspace.url(path)
            let pdf = try XCTUnwrap(PDFDocument(data: bytes)); pdf.page(at: 0)?.rotation = rotation
            XCTAssertTrue(pdf.write(to: url))
            var page = PageSnapshot(); page.pdfFile = path; page.pdfIndex = 0
            page.width = rotation % 180 == 0 ? 600 : 800; page.height = rotation % 180 == 0 ? 800 : 600
            let words = try await PDFTextReader.shared.words(url: url, index: 0, pageWidth: page.width, pageHeight: page.height)
            let word = try XCTUnwrap(words.first(where: { $0.text == "Energia" }))
            let image = try XCTUnwrap(DocumentServices.image(page: page, drawing: PKDrawing(), workspace: workspace).cgImage)
            let factor = CGAffineTransform(scaleX: CGFloat(image.width) / page.width, y: CGFloat(image.height) / page.height)
            let crop = try XCTUnwrap(image.cropping(to: word.rect.insetBy(dx: -1, dy: -1).applying(factor).integral))
            XCTAssertGreaterThan(pixelCount(crop, white: false), 30, "I riquadri devono coprire i glifi reali anche a \(rotation)°.")
        }
    }
    @MainActor func testTwelveEraserUpdatesReuseOnePaperImageAndKeepWhiteInk() throws {
        var page = PageSnapshot(); page.width = 300; page.height = 200; page.appearance = .init(tone: .slate)
        var drawing = PKDrawing(strokes: [ink(.marker, color: .yellow, y: 70, width: 24), ink(.pen, color: .white, y: 70, width: 4)])
        let cache = MarkerCompositionCache(), token = UUID(), bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        var rendered = UIImage()
        for index in 0..<12 {
            drawing = SelectiveInkEraser.erase(drawing, samples: [.init(x: 50 + Double(index) * 12, y: 70)], width: 8, wholeStroke: false).0
            rendered = renderer.image { item in
                cache.drawReplacingInk(page: page, drawing: drawing, token: token, package: URL(fileURLWithPath: "/"),
                    bounds: bounds, scale: 2, hiddenIDs: [], hiddenTextID: nil, in: item.cgContext)
            }
        }
        XCTAssertEqual(cache.builds, 1, "Cambiare le maschere dell’evidenziatore non deve ridisegnare PDF e carta dodici volte.")
        XCTAssertEqual(drawing.strokes.last?.ink.inkType, .pen)
        let image = try XCTUnwrap(rendered.cgImage)
        let strip = try XCTUnwrap(image.cropping(to: CGRect(x: 100, y: 134, width: 360, height: 12)))
        XCTAssertGreaterThan(pixelCount(strip, white: true), 80)
    }
    @MainActor private func pixelCount(_ image: CGImage, white: Bool) -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
            context.draw(image, in: .init(x: 0, y: 0, width: width, height: height))
            let p = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: p.count, by: 4).filter { i in
                white ? p[i] > 235 && p[i + 1] > 235 && p[i + 2] > 235 : p[i] < 30 && p[i + 1] < 30 && p[i + 2] < 30
            }.count
        }
    }
}
