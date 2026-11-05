import XCTest
import UIKit
import PDFKit
import PencilKit
@testable import NeuralNotes

final class LayerBlendCompositorTests: XCTestCase {
    @MainActor func testPDFCoefficientGlyphOutlinesMatchTheFinalTextLayoutWithoutEmittingExtraText() throws {
        let value = NSAttributedString(string: "Layer text", attributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        let box = CGRect(x: 5, y: 20, width: 110, height: 75)
        let normal = image(background: .white) { context in
            LayerPDFText.layout(true) { LayerPDFText.draw(value, in: box, context: context) }
        }
        let outlines = image(background: .white) { context in
            LayerPDFText.layout(true) { LayerPDFText.outlines(true) { LayerPDFText.draw(value, in: box, context: context) } }
        }
        for (name, value) in [("layer-pdf-text-final-glyphs", normal), ("layer-pdf-text-coefficient-outlines", outlines)] {
            let attachment = XCTAttachment(image: value); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        var total = 0, samples = 0, inkNormal = 0, inkOutlines = 0
        for y in stride(from: 20, to: 90, by: 2) { for x in stride(from: 5, to: 115, by: 2) {
            let a = try pixel(normal, at: CGPoint(x: x, y: y)), b = try pixel(outlines, at: CGPoint(x: x, y: y))
            for channel in 0..<3 { total += abs(Int(a[channel]) - Int(b[channel])); samples += 1 }
            if a[0] < 128 { inkNormal += 1 }; if b[0] < 128 { inkOutlines += 1 }
        } }
        XCTAssertGreaterThan(inkNormal, 50); XCTAssertGreaterThan(inkOutlines, 50)
        XCTAssertLessThanOrEqual(Double(total) / Double(samples), 3)
        XCTAssertLessThanOrEqual(abs(inkNormal - inkOutlines), max(3, inkNormal / 10))
    }
    @MainActor func testPreparedNativeMarkerUsesMultiplyOverBlackTextRatherThanPaintingItsWhiteMatte() throws {
        let a = PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0, size: CGSize(width: 22, height: 22), opacity: 0.4, force: 1, azimuth: 0, altitude: .pi / 2)
        let b = PKStrokePoint(location: CGPoint(x: 110, y: 20), timeOffset: 1, size: CGSize(width: 22, height: 22), opacity: 0.4, force: 1, azimuth: 0, altitude: .pi / 2)
        let stroke = PKStroke(ink: PKInk(.marker, color: .yellow), path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: 1000)))
        let prepared = PreparedLayerInk(drawing: PKDrawing(strokes: [stroke]), bounds: bounds, scale: 1)
        let result = image(background: .white) { context in
            context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(x: 30, y: 10, width: 20, height: 25))
            prepared.drawMarkers(in: context)
        }
        let black = try pixel(result, at: CGPoint(x: 40, y: 20))
        XCTAssertTrue(black.prefix(3).allSatisfy { $0 < 3 }, "The marker matte must never replace existing black PDF text")
        let paper = try pixel(result, at: CGPoint(x: 80, y: 20))
        XCTAssertGreaterThan(Int(paper[0]), Int(paper[2]) + 20)
        XCTAssertTrue(try pixel(result, at: CGPoint(x: 5, y: 95)).prefix(3).allSatisfy { $0 > 250 })
    }
    private let bounds = CGRect(x: 0, y: 0, width: 120, height: 100)
    @MainActor private func image(background: UIColor, drawing: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { value in
            value.cgContext.setFillColor(background.cgColor); value.cgContext.fill(bounds)
            drawing(value.cgContext)
        }
    }
    @MainActor private func content(_ context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.setBlendMode(.multiply); context.setFillColor(UIColor(red: 1, green: 0.83, blue: 0.12, alpha: 0.4).cgColor)
        context.fill(CGRect(x: 10, y: 10, width: 100, height: 25))
        context.setBlendMode(.normal); context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 10, y: 45, width: 70, height: 30))
        context.setFillColor(UIColor.blue.cgColor); context.fill(CGRect(x: 40, y: 45, width: 70, height: 30))
        context.setFillColor(UIColor.white.cgColor); context.fill(CGRect(x: 10, y: 82, width: 100, height: 10))
    }
    @MainActor private func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }

    @MainActor func testBitmapMapsAndVectorGroupsMatchWholeLayerOpacityOnRealBackdrops() throws {
        let samples = [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 55), CGPoint(x: 55, y: 55), CGPoint(x: 100, y: 55), CGPoint(x: 30, y: 87), CGPoint(x: 2, y: 2)]
        for background in [UIColor.white, .black, UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)] {
            let base = image(background: background) { _ in }
            let full = image(background: background, drawing: content)
            for opacity in [0.0, 0.25, 0.5, 0.9, 1.0] {
                let maps = try XCTUnwrap(LayerBlendCompositor.maps(opacity: opacity, bounds: bounds, scale: 1, content: content))
                let raster = image(background: background) { maps.draw(in: $0, bounds: bounds) }
                let vector = image(background: background) { LayerBlendCompositor.drawGroup(opacity: opacity, bounds: bounds, in: $0, content: content) }
                for point in samples {
                    let initial = try pixel(base, at: point), complete = try pixel(full, at: point)
                    let cached = try pixel(raster, at: point), actual = try pixel(vector, at: point)
                    for channel in 0..<3 {
                        let expected = Int((Double(initial[channel]) * (1 - opacity) + Double(complete[channel]) * opacity).rounded())
                        XCTAssertLessThanOrEqual(abs(Int(cached[channel]) - expected), 3, "Cached group differs from real backdrop/opacity at \(point)")
                        XCTAssertLessThanOrEqual(abs(Int(actual[channel]) - expected), 3, "Vector group differs from real backdrop/opacity at \(point)")
                    }
                }
                XCTAssertLessThanOrEqual(maps.byteCost, 128 * 100 * 8)
            }
        }
    }

    @MainActor func testMarkerNeverLightensBlackTextAndWhiteInkDoesNotMultiplyIntoDarkPaper() throws {
        let result = image(background: .white) { context in
            context.setFillColor(UIColor.black.cgColor); context.fill(CGRect(x: 10, y: 10, width: 30, height: 25))
            LayerBlendCompositor.drawGroup(opacity: 0.5, bounds: bounds, in: context, content: content)
        }
        let black = try pixel(result, at: CGPoint(x: 20, y: 20))
        XCTAssertLessThan(black[0], 3); XCTAssertLessThan(black[1], 3); XCTAssertLessThan(black[2], 3)
        let dark = image(background: .black) { LayerBlendCompositor.drawGroup(opacity: 0.5, bounds: bounds, in: $0, content: content) }
        let white = try pixel(dark, at: CGPoint(x: 30, y: 87))
        for channel in white.prefix(3) { XCTAssertLessThanOrEqual(abs(Int(channel) - 128), 3) }
    }

    @MainActor func testPartialOpacityPDFKeepsOriginalSelectableTextAndNativeVectorInkWithoutImageXObjects() throws {
        let a = PKStrokePoint(location: CGPoint(x: 10, y: 40), timeOffset: 0, size: CGSize(width: 6, height: 6), opacity: 1, force: 0.7, azimuth: 0.2, altitude: 1)
        let b = PKStrokePoint(location: CGPoint(x: 100, y: 40), timeOffset: 1, size: CGSize(width: 9, height: 9), opacity: 1, force: 0.9, azimuth: 0.4, altitude: 1)
        let native = PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: 1000)))
        let drawing = PKDrawing(strokes: [native])
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            renderer.beginPage()
            ("BASE UNIQUE" as NSString).draw(at: CGPoint(x: 4, y: 3), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            LayerBlendCompositor.drawGroup(opacity: 0.5, bounds: bounds, in: renderer.cgContext) { context in
                self.content(context); VectorInkRenderer.draw(drawing, in: context)
            }
        }
        let document = try XCTUnwrap(PDFDocument(data: data)), text = try XCTUnwrap(document.page(at: 0)?.string)
        XCTAssertEqual(text.components(separatedBy: "BASE UNIQUE").count - 1, 1)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData)), pdf = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(pdf.page(at: 1)), dictionary = try XCTUnwrap(page.dictionary)
        XCTAssertFalse(PDFResourceProbe.hasImages(dictionary), "Layer opacity must not rasterize native ink or the PDF")
        let preview = try XCTUnwrap(document.page(at: 0)).thumbnail(of: bounds.size, for: .mediaBox)
        let blue = try pixel(preview, at: CGPoint(x: 80, y: 40))
        XCTAssertGreaterThan(Int(blue[2]), Int(blue[0]) + 50)
    }

    @MainActor func testMapsRefuseUnboundedBuffersAndLeaveTheRequestedOriginIntact() throws {
        XCTAssertNil(LayerBlendCompositor.maps(opacity: 0.5, bounds: CGRect(x: 0, y: 0, width: 10000, height: 10000), scale: 2, content: content))
        let offset = CGRect(x: 200, y: 300, width: 20, height: 20)
        let maps = try XCTUnwrap(LayerBlendCompositor.maps(opacity: 0.5, bounds: offset, scale: 1) { context in
            context.setFillColor(UIColor.red.cgColor); context.fill(offset)
        })
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: offset.size, format: format).image { renderer in
            renderer.cgContext.translateBy(x: -offset.minX, y: -offset.minY)
            renderer.cgContext.setFillColor(UIColor.white.cgColor); renderer.cgContext.fill(offset)
            maps.draw(in: renderer.cgContext, bounds: offset)
        }
        let red = try pixel(result, at: CGPoint(x: 10, y: 10))
        XCTAssertGreaterThan(red[0], 250); XCTAssertLessThanOrEqual(abs(Int(red[1]) - 128), 3)
    }
}
