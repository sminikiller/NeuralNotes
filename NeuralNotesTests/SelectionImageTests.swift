import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class SelectionImageTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor func testTransparentTwoTimesPNGExcludesPDFAndUnselectedObjects() async throws {
        try await fixture { model in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("selection-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).writePDF(to: file) { item in
                item.beginPage(); ("PDF DA ESCLUDERE" as NSString).draw(at: CGPoint(x: 110, y: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
            }
            await model.importPages(from: file); XCTAssertNil(model.error)
            let selected = ShapeElement(kind: .ellipse, x: 80, y: 100, width: 280, height: 200, red: 1, lineWidth: 4)
            var other = ShapeElement(kind: .rectangle, x: 150, y: 180, width: 60, height: 40, blue: 1)
            other.fill = InkColor(0, 0, 1)
            model.page?.shapes = [selected, other]; model.selectedIDs = [selected.id]
            let bounds = model.selectionBounds.insetBy(dx: -2, dy: -2)
            let image = try model.selectionImage(), cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(image.scale, 2); XCTAssertEqual(cg.width, Int(ceil(bounds.width * 2)))
            XCTAssertEqual(cg.height, Int(ceil(bounds.height * 2)))
            let data = pixels(cg)
            var transparent = 0, red = 0, black = 0, blue = 0
            for i in stride(from: 0, to: data.count, by: 4) {
                if data[i + 3] == 0 { transparent += 1 }
                if data[i + 3] > 100 {
                    if data[i] > 150 && data[i + 1] < 50 && data[i + 2] < 50 { red += 1 }
                    if data[i] < 30 && data[i + 1] < 30 && data[i + 2] < 30 { black += 1 }
                    if data[i + 2] > 150 && data[i] < 50 { blue += 1 }
                }
            }
            XCTAssertGreaterThan(transparent, cg.width * cg.height / 2); XCTAssertGreaterThan(red, 100)
            XCTAssertEqual(black, 0); XCTAssertEqual(blue, 0)
            let decoded = try XCTUnwrap(UIImage(data: try XCTUnwrap(image.pngData()))?.cgImage)
            let decodedPixels = pixels(decoded)
            XCTAssertTrue(stride(from: 3, to: decodedPixels.count, by: 4).contains { decodedPixels[$0] == 0 })
        }
    }
    @MainActor func testSelectionExportsOnlyChosenInkAndIncludesSelectedTape() async throws {
        try await fixture { model in
            func stroke(_ color: UIColor, y: CGFloat) -> PKStroke {
                let controls = [CGPoint(x: 100, y: y), CGPoint(x: 300, y: y)].enumerated().map { index, point in
                    PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
            }
            model.canvas.drawing = PKDrawing(strokes: [stroke(.red, y: 140), stroke(.blue, y: 170)])
            let tape = StudyTape(x: 100, y: 200, width: 80, height: 40)
            model.page?.tapes = [tape]; model.selectedIDs = [tape.id]; model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            let image = try XCTUnwrap(model.selectionImage().cgImage), data = pixels(image)
            var red = 0, blue = 0, yellow = 0
            for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 100 {
                if data[i] > 150 && data[i + 1] < 50 && data[i + 2] < 50 { red += 1 }
                if data[i + 2] > 150 && data[i] < 50 { blue += 1 }
                if data[i] > 180 && data[i + 1] > 130 && data[i + 2] < 100 { yellow += 1 }
            }
            XCTAssertGreaterThan(red, 100); XCTAssertGreaterThan(yellow, 100); XCTAssertEqual(blue, 0)
        }
    }
    @MainActor func testRotatedImageBoundsMatchTheRendererAndLargeSelectionIsRefusedBeforeAllocation() async throws {
        try await fixture { model in
            var image = ImageElement(file: "images/not-needed.png", width: 200, height: 100)
            image.x = 100; image.y = 200; image.rotation = 90
            model.page?.images = [image]; model.selectedIDs = [image.id]
            XCTAssertEqual(model.selectionBounds.width, 200, accuracy: 0.01)
            XCTAssertEqual(model.selectionBounds.height, 100, accuracy: 0.01)
            image.rotation = 45; model.page?.images = [image]
            XCTAssertEqual(model.selectionBounds.width, 300 / sqrt(2), accuracy: 0.01)
            XCTAssertEqual(model.selectionBounds.midX, 200, accuracy: 0.01)
            image.width = 5000; image.height = 5000; model.page?.images = [image]
            XCTAssertThrowsError(try model.selectionImage())
        }
    }
    @MainActor private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
