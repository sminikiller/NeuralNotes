import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class PhotoPerspectiveTests: XCTestCase {
    @MainActor private func fixture() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 120), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 60, width: 200, height: 60))
        }
    }
    @MainActor private func rgb(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage); var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
    @MainActor func testCorrectionThenCropRotationAndExifOrientation() throws {
        let source = fixture()
        let top = try XCTUnwrap(PhotoPerspective.render(source, adjustment: .init(crop: .init(x: 0, y: 0, width: 1, height: 0.4), perspective: .full)))
        let pixel = try rgb(top); XCTAssertGreaterThan(pixel[0], 220); XCTAssertLessThan(pixel[2], 30)
        let rotated = try XCTUnwrap(PhotoPerspective.render(source, adjustment: .init(perspective: .full, quarterTurns: 1, enhanced: true)))
        XCTAssertEqual(rotated.size.width, 120, accuracy: 1); XCTAssertEqual(rotated.size.height, 200, accuracy: 1)
        let exif = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .right)
        let normalized = try XCTUnwrap(PhotoPerspective.render(exif, adjustment: .init()))
        XCTAssertEqual(normalized.imageOrientation, .up); XCTAssertEqual(normalized.size.width, 120, accuracy: 1)
        XCTAssertEqual(normalized.size.height, 200, accuracy: 1)
        let quad = PerspectiveQuad(topLeft: .init(x: 0.1, y: 0.1), topRight: .init(x: 0.9, y: 0.15),
            bottomRight: .init(x: 0.85, y: 0.9), bottomLeft: .init(x: 0.15, y: 0.85))
        let correction = try XCTUnwrap(PhotoPerspective.render(source, adjustment: .init(perspective: quad)))
        let expected = try XCTUnwrap(quad.outputSize(for: .init(width: 200, height: 120)))
        XCTAssertEqual(correction.size.width, expected.width, accuracy: 2)
        XCTAssertEqual(correction.size.height, expected.height, accuracy: 2)
    }
    @MainActor func testCacheIncludesEveryAdjustmentAndSourceIsNeverOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try XCTUnwrap(fixture().pngData()); try data.write(to: file)
        let cache = DocumentRenderCache()
        let first = try XCTUnwrap(cache.croppedImage(file, crop: .full, perspective: .full, quarterTurns: 1))
        let again = try XCTUnwrap(cache.croppedImage(file, crop: .full, perspective: .full, quarterTurns: 1))
        XCTAssertTrue(first === again)
        let second = try XCTUnwrap(cache.croppedImage(file, crop: .full, perspective: .full, quarterTurns: 2))
        XCTAssertNotEqual(first.size, second.size)
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
    @MainActor func testPhotoEditUndoRedoAndExportPreserveStoredOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        _ = try await workspace.addPage()
        let model = EditorViewModel(workspace: workspace); await model.open(); defer { Task { _ = await model.close() } }
        let data = try XCTUnwrap(fixture().pngData()), image = try await DocumentServices.importImage(data: data, into: workspace)
        model.addImage(image)
        model.rotateSelectedImage()
        let source = workspace.package.appendingPathComponent(image.file), original = try Data(contentsOf: source)
        let edit = PhotoAdjustment(crop: .init(x: 0, y: 0, width: 0.8, height: 1), perspective: .full, quarterTurns: 1, enhanced: true)
        model.straightenSelectedImage(edit)
        XCTAssertEqual(model.page?.images.first?.photoAdjustment, edit)
        let corrected = try XCTUnwrap(model.page?.images.first)
        XCTAssertEqual(corrected.rotation, 90)
        XCTAssertEqual(corrected.height / corrected.width, 0.48, accuracy: 0.01, "Keep the bounding aspect of an image rotated before perspective editing")
        await model.performUndo(); XCTAssertNil(model.page?.images.first?.perspective)
        await model.performRedo(); XCTAssertEqual(model.page?.images.first?.photoAdjustment, edit)
        let flushed = await model.flush(); XCTAssertTrue(flushed)
        let pdf = try await DocumentServices.exportPDF(workspace: workspace)
        XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let closed = await model.close(); XCTAssertTrue(closed)
    }
}
