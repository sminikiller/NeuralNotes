import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class MarkerAndRecognitionTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await run(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func stroke(_ points: [CGPoint], marker: Bool = false, width: CGFloat = 3) -> PKStroke {
        let controls = points.enumerated().map { index, point in PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
            size: .init(width: width, height: width), opacity: marker ? 0.4 : 1, force: 0.7, azimuth: 0, altitude: .pi / 2) }
        return PKStroke(ink: PKInk(marker ? .marker : .pen, color: marker ? .yellow : .black), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
    }
    @MainActor func testHeldRecognitionSurvivesJitterAndTheNextNativeStrokeDoesNotRestoreRawInk() async throws {
        try await fixture { model in
            model.editShapePreferences { $0.mode = .hold; $0.output = .editable }
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model); host.drawingAssistant = assistant; model.drawingAssistant = assistant
            let points = (0...50).map { CGPoint(x: 100 + CGFloat($0) * 5, y: 200 + sin(CGFloat($0))) }
            assistant.begin(at: points[0]); model.strokeBegan(); assistant.move(samples: Array(points.dropFirst()))
            model.canvas.drawing = PKDrawing(strokes: [stroke(points)])
            let rawSignature = try XCTUnwrap(EditorInkSignatures.make(model.canvas.drawing).first)
            assistant.recognizeHold(); let recognized = try XCTUnwrap(model.pendingShapeRecognition)
            assistant.move(samples: [.init(x: 350.7, y: 200.4), .init(x: 349.9, y: 200.2)])
            XCTAssertEqual(model.pendingShapeRecognition?.shape, recognized.shape)
            XCTAssertEqual(model.canvas.layer.opacity, 0)
            assistant.end(cancelled: false); model.strokeEnded(); model.finishInkGesture()
            let shape = try XCTUnwrap(model.page?.shapes?.first)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            model.strokeBegan()
            let second = stroke([.init(x: 150, y: 400), .init(x: 210, y: 420)])
            model.canvas.drawing = PKDrawing(strokes: model.canvas.drawing.strokes + [second])
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertFalse(EditorInkSignatures.make(model.canvas.drawing).contains(rawSignature))
            XCTAssertEqual(model.page?.shapes?.first, shape)
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertEqual(model.page?.shapes?.first, shape)
            await model.performUndo(); XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), [rawSignature]); XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            await model.performRedo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertEqual(model.page?.shapes?.first, shape)
        }
    }
    @MainActor func testOnePointMarkerAndDigitalPDFWordSelectionPreserveBlackTextAndUndoTogether() async throws {
        try await fixture { model in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("marker-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            try UIGraphicsPDFRenderer(bounds: .init(x: 0, y: 0, width: 600, height: 800)).writePDF(to: file) { renderer in
                renderer.beginPage()
                ("Energia conservata" as NSString).draw(at: .init(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
                ("Seconda riga intatta" as NSString).draw(at: .init(x: 60, y: 126), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
            }
            await model.importPages(from: file); XCTAssertNil(model.error)
            model.chooseTool(.marker); model.chooseMarkerWidth(1)
            XCTAssertEqual((model.canvas.tool as? PKInkingTool)?.width, 1)
            for _ in 0..<200 where !model.markerWordsActive { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(model.markerWordsActive)
            let page = try XCTUnwrap(model.page), words = PageWordIndex.shared.pdfWords(page)
            let target = try XCTUnwrap(words.first(where: { $0.text == "Energia" }))
            let baseline = DocumentServices.image(page: page, drawing: PKDrawing(), workspace: model.workspace)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let session = try XCTUnwrap(MarkerWordSession(host: host, model: model))
            session.move([CGPoint(x: target.rect.midX, y: target.rect.midY)]); session.finish(cancelled: false)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let marker = try XCTUnwrap(model.canvas.drawing.strokes.first)
            XCTAssertLessThanOrEqual(marker.renderBounds.maxY, words.first(where: { $0.text == "Seconda" })?.rect.minY ?? 0)
            let marked = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace)
            XCTAssertGreaterThan(blackPixels(baseline), 100)
            XCTAssertGreaterThanOrEqual(blackPixels(marked), Int(Double(blackPixels(baseline)) * 0.98), "Il colore non deve schiarire i glifi neri del PDF.")
            XCTAssertFalse(host.markerReadability.isUserInteractionEnabled)
            let saved = await model.flush(); XCTAssertTrue(saved)
            let exported = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: exported) }
            XCTAssertEqual(PDFDocument(url: exported)?.pageCount, 2)
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }
    @MainActor private func blackPixels(_ image: UIImage) -> Int {
        guard let image = image.cgImage else { return 0 }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
            context.draw(image, in: .init(x: 0, y: 0, width: width, height: height))
            let data = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: data.count, by: 4).filter { data[$0] < 30 && data[$0 + 1] < 30 && data[$0 + 2] < 30 }.count
        }
    }
}
