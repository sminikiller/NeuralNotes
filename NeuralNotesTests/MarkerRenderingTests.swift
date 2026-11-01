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
                cache.drawReplacingContent(page: page, drawing: drawing, token: token, package: URL(fileURLWithPath: "/"),
                    bounds: bounds, scale: 2, hiddenIDs: [], hiddenTextID: nil, in: item.cgContext)
            }
        }
        XCTAssertEqual(cache.builds, 1, "Cambiare le maschere dell’evidenziatore non deve ridisegnare PDF e carta dodici volte.")
        XCTAssertEqual(drawing.strokes.last?.ink.inkType, .pen)
        let image = try XCTUnwrap(rendered.cgImage)
        let strip = try XCTUnwrap(image.cropping(to: CGRect(x: 100, y: 134, width: 360, height: 12)))
        XCTAssertGreaterThan(pixelCount(strip, white: true), 80)
    }
    @MainActor func testErasedObjectsAndMarkupNeverReappearInTheCachedPDFComposition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: root.appendingPathComponent("attachments/paper.pdf")) { item in
            item.beginPage(); ("ENERGIA" as NSString).draw(at: CGPoint(x: 30, y: 55), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.black])
        }
        var page = PageSnapshot(); page.width = 300; page.height = 200; page.pdfFile = "attachments/paper.pdf"; page.pdfIndex = 0
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format), cache = MarkerCompositionCache(), token = UUID()
        let baseline = renderer.image { item in PageRenderer.draw(page, package: root, in: item.cgContext) }
        var shape = ShapeElement(kind: .rectangle, x: 185, y: 50, width: 50, height: 40, red: 1, green: 0, blue: 0)
        shape.fill = .red; shape.fillOpacity = 1; page.shapes = [shape]
        page.pdfMarkups = [.init(kind: .highlight, x: 20, y: 110, width: 80, height: 12, text: "Rimuovere")]
        let drawing = PKDrawing(strokes: [ink(.marker, color: .yellow, y: 70, width: 24)])
        let before = renderer.image { item in cache.drawReplacingContent(page: page, drawing: drawing, token: token, package: root, bounds: bounds, scale: 2, hiddenIDs: [], hiddenTextID: nil, in: item.cgContext) }
        page.shapes = []; page.pdfMarkups = []; page.revision += 1
        let after = renderer.image { item in cache.drawReplacingContent(page: page, drawing: drawing, token: token, package: root, bounds: bounds, scale: 2, hiddenIDs: [], hiddenTextID: nil, in: item.cgContext) }
        XCTAssertEqual(cache.builds, 1)
        let redBox = CGRect(x: 380, y: 110, width: 80, height: 60)
        let markedBox = CGRect(x: 40, y: 220, width: 160, height: 24)
        let oldShape = try XCTUnwrap(before.cgImage?.cropping(to: redBox)), newShape = try XCTUnwrap(after.cgImage?.cropping(to: redBox))
        XCTAssertGreaterThan(pixelCount(oldShape, white: false, red: true), 100)
        XCTAssertEqual(pixelCount(newShape, white: false, red: true), 0)
        let oldMark = try XCTUnwrap(before.cgImage?.cropping(to: markedBox)), newMark = try XCTUnwrap(after.cgImage?.cropping(to: markedBox))
        XCTAssertGreaterThan(pixelCount(newMark, white: true), pixelCount(oldMark, white: true) + 100)
        XCTAssertGreaterThanOrEqual(pixelCount(try XCTUnwrap(after.cgImage), white: false), Int(Double(pixelCount(try XCTUnwrap(baseline.cgImage), white: false)) * 0.98))
    }
    @MainActor func testLiveWordAndFreehandMarkerHaveTheSameColorAndPreserveThePDFText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: root.appendingPathComponent("attachments/text.pdf")) { item in
            item.beginPage(); ("Energia" as NSString).draw(at: CGPoint(x: 40, y: 55), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
        }
        var page = PageSnapshot(); page.width = 300; page.height = 200; page.paper = .plain
        page.pdfFile = "attachments/text.pdf"; page.pdfIndex = 0
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let path = UIBezierPath(rect: CGRect(x: 30, y: 50, width: 230, height: 35)).cgPath
        let color = UIColor(red: InkColor.yellow.red, green: InkColor.yellow.green, blue: InkColor.yellow.blue, alpha: 1)
        let cache = MarkerCompositionCache(), token = UUID()
        let preview = renderer.image { item in cache.drawLiveMarker(page: page, baseline: PKDrawing(), token: token, footprint: path,
            color: color, package: root, bounds: bounds, scale: 1, in: item.cgContext) }
        let controls = [CGPoint(x: 30, y: 67.5), CGPoint(x: 260, y: 67.5)].enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i) * 0.1, size: .init(width: 35, height: 35), opacity: 0.25, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.marker, color: color), path: PKStrokePath(controlPoints: controls, creationDate: Date()))])
        let free = renderer.image { item in PageRenderer.draw(page, package: root, in: item.cgContext); LegibleInkRenderer.draw(drawing, in: item.cgContext, bounds: bounds, scale: 1) }
        var mark = PDFMarkup(kind: .highlight, x: 30, y: 50, width: 230, height: 35, text: "Energia")
        mark.wordHighlight = true; mark.color = .yellow; mark.opacity = 0.25; page.pdfMarkups = [mark]
        let words = renderer.image { PageRenderer.draw(page, package: root, in: $0.cgContext) }
        func pixel(_ image: UIImage) throws -> [UInt8] {
            let source = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 200, y: 65, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }; return rgba
        }
        let liveColor = try pixel(preview), freeColor = try pixel(free), wordColor = try pixel(words)
        for channel in 0..<3 {
            XCTAssertEqual(Double(liveColor[channel]), Double(freeColor[channel]), accuracy: 2)
            XCTAssertEqual(Double(wordColor[channel]), Double(freeColor[channel]), accuracy: 2)
        }
        let blackBefore = pixelCount(try XCTUnwrap(words.cgImage), white: false)
        XCTAssertGreaterThan(blackBefore, 100)
        // Black glyphs are preserved in both preview and saved freehand pixels.
        XCTAssertGreaterThanOrEqual(pixelCount(try XCTUnwrap(free.cgImage), white: false), Int(Double(blackBefore) * 0.98))
        XCTAssertGreaterThanOrEqual(pixelCount(try XCTUnwrap(preview.cgImage), white: false), Int(Double(blackBefore) * 0.98))
        XCTAssertEqual(cache.builds, 1)
    }
    @MainActor private func pixelCount(_ image: CGImage, white: Bool, red: Bool = false) -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
            context.draw(image, in: .init(x: 0, y: 0, width: width, height: height))
            let p = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: p.count, by: 4).filter { i in
                if red { return p[i] > 150 && p[i + 1] < 100 && p[i + 2] < 100 }
                return white ? p[i] > 235 && p[i + 1] > 235 && p[i + 2] > 235 : p[i] < 30 && p[i + 1] < 30 && p[i + 2] < 30
            }.count
        }
    }
}
