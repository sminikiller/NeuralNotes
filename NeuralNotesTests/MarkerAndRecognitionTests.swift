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
            XCTAssertEqual(model.markerWidth, 1); XCTAssertTrue(model.markerCustomInput)
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled, "La modalità Parole intercetta il gesto senza aggiungere pennarello nativo.")
            for _ in 0..<200 where !model.markerWordsActive { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(model.markerWordsActive)
            let page = try XCTUnwrap(model.page), words = PageWordIndex.shared.pdfWords(page)
            let target = try XCTUnwrap(words.first(where: { $0.text == "Energia" }))
            let baseline = DocumentServices.image(page: page, drawing: PKDrawing(), workspace: model.workspace)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let session = try XCTUnwrap(MarkerWordSession(host: host, model: model))
            session.move([CGPoint(x: target.rect.midX, y: target.rect.midY)]); session.finish(cancelled: false)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            let marker = try XCTUnwrap(model.page?.pdfMarkups?.first)
            XCTAssertEqual(model.page?.pdfMarkups?.count, 1); XCTAssertEqual(marker.wordHighlight, true)
            XCTAssertEqual(marker.text, "Energia"); XCTAssertEqual(marker.color, InkColor(model.ink))
            XCTAssertLessThanOrEqual(marker.y + marker.height, Double(words.first(where: { $0.text == "Seconda" })?.rect.minY ?? 0))
            let marked = DocumentServices.image(page: try XCTUnwrap(model.page), drawing: model.canvas.drawing, workspace: model.workspace)
            XCTAssertGreaterThan(blackPixels(baseline), 100)
            XCTAssertGreaterThanOrEqual(blackPixels(marked), Int(Double(blackPixels(baseline)) * 0.98), "Il colore non deve schiarire i glifi neri del PDF.")
            XCTAssertFalse(host.markerReadability.isUserInteractionEnabled)
            let saved = await model.flush(); XCTAssertTrue(saved)
            let exported = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: exported) }
            XCTAssertEqual(PDFDocument(url: exported)?.pageCount, 2)
            await model.performUndo(); XCTAssertTrue(model.page?.pdfMarkups?.isEmpty ?? true)
            await model.performRedo(); XCTAssertEqual(model.page?.pdfMarkups?.count, 1)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testFreehandMarkerBelowNativeMinimumStoresOnePointWideVectorInkAndUndoesOnce() async throws {
        try await fixture { model in
            model.editWriting { $0.markerSnapWords = false }
            model.chooseTool(.marker); model.editShapePreferences { $0.mode = .off }; model.chooseMarkerWidth(1)
            XCTAssertTrue(model.markerCustomInput); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model); host.drawingAssistant = assistant; model.drawingAssistant = assistant
            assistant.begin(at: .init(x: 100, y: 200))
            assistant.move(samples: [.init(x: 150, y: 200), .init(x: 220, y: 200)])
            assistant.end(cancelled: false)
            let ink = try XCTUnwrap(model.canvas.drawing.strokes.first)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1); XCTAssertEqual(ink.ink.inkType, .marker)
            XCTAssertTrue(ink.path.allSatisfy { $0.size.width == 1 && $0.size.height == 1 })
            XCTAssertLessThanOrEqual(ink.renderBounds.height, 3, "Anche il renderer PencilKit deve rispettare il tratto sottile.")
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }
    @MainActor func testMarkerPreparationOfAScannedPDFDoesNotPreventLensOCR() async throws {
        try await fixture { model in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
            let scan = UIGraphicsImageRenderer(size: bounds.size).image { renderer in
                UIColor.white.setFill(); renderer.fill(bounds)
                ("ENERGIA CONSERVATA" as NSString).draw(at: .init(x: 50, y: 150), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.black])
            }
            try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: file) { renderer in renderer.beginPage(); scan.draw(in: bounds) }
            XCTAssertTrue(PDFDocument(url: file)?.page(at: 0)?.string?.isEmpty ?? true)
            await model.importPages(from: file); XCTAssertNil(model.error)
            let page = try XCTUnwrap(model.page), index = PageWordIndex.shared
            model.chooseTool(.marker)
            // Choosing word highlighting starts the same scan OCR as the Lens.
            let recognized = Date().addingTimeInterval(10)
            while !index.isReady(page), Date() < recognized { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(index.isReady(page))
            XCTAssertTrue(index.groups(for: page).flatMap { $0 }.contains { $0.text.localizedCaseInsensitiveContains("ENERGIA") })
            XCTAssertTrue(index.pdfWords(page).isEmpty, "Le parole OCR della scansione non si devono spacciare per testo digitale del PDF.")
            XCTAssertTrue(model.markerWordsActive)
            let target = try XCTUnwrap(index.markerWords(page).first { $0.text.localizedCaseInsensitiveContains("ENERGIA") })
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let session = try XCTUnwrap(MarkerWordSession(host: host, model: model))
            session.move([.init(x: target.rect.midX, y: target.rect.midY)]); session.finish(cancelled: false)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertEqual(model.page?.pdfMarkups?.count, 1)
            XCTAssertTrue(index.isReady(page)); XCTAssertTrue(model.markerWordsActive, "Evidenziare una parola non deve far dimenticare le altre.")
            await model.performUndo(); XCTAssertTrue(model.page?.pdfMarkups?.isEmpty ?? true)
            XCTAssertTrue(index.isReady(page)); XCTAssertTrue(model.markerWordsActive)
            await model.performRedo(); XCTAssertEqual(model.page?.pdfMarkups?.count, 1)
            XCTAssertTrue(index.isReady(page)); XCTAssertTrue(model.markerWordsActive)
            model.chooseTool(.eraser); model.editWriting { $0.markerOnly = true; $0.eraser = .partial; $0.eraserWidth = 12 }
            let markerBeforeErase = model.canvas.drawing.dataRepresentation()
            model.drawingShape = true
            let erasing = SelectiveEraseSession(model: model)
            erasing.append([.init(x: target.rect.midX, y: target.rect.midY)])
            model.drawingShape = false; erasing.finish(cancelled: false)
            XCTAssertNil(model.eraserCompositionToken)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, try PKDrawing(data: markerBeforeErase)))
            XCTAssertTrue(model.page?.pdfMarkups?.isEmpty == true)
            XCTAssertTrue(index.isReady(page), "La gomma solo evidenziatore deve conservare l’OCR anche dopo la fine del gesto.")
            await model.performUndo(); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, try PKDrawing(data: markerBeforeErase)))
            XCTAssertEqual(model.page?.pdfMarkups?.count, 1)
            XCTAssertTrue(index.isReady(page))
            model.chooseTool(.pen); model.editShapePreferences { $0.mode = .off }
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: model.canvas.drawing.strokes + [stroke([.init(x: 60, y: 400), .init(x: 220, y: 400)])])
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertFalse(index.isReady(page), "Il nuovo inchiostro deve rendere obsoleto l’OCR precedente.")
            model.chooseTool(.marker)
            XCTAssertFalse(model.markerWordsActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            // A partial eraser preserves path creation dates. Undo must compare
            // visible ink, rather than those audio identities, to expire OCR.
            model.chooseTool(.eraser)
            let fullInk = model.canvas.drawing, beforeMask = model.captureEdit(ink: true)
            let clipped = fullInk.strokes.map { stroke -> PKStroke in
                guard stroke.ink.inkType != .marker else { return stroke }
                return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform,
                    mask: UIBezierPath(rect: CGRect(x: 60, y: 390, width: 80, height: 20)))
            }
            model.canvas.drawing = PKDrawing(strokes: clipped)
            XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), EditorInkSignatures.make(fullInk))
            model.recordEdit(beforeMask, label: "Cancella parte della penna"); model.drawingChanged()
            index.prepare(page, model: model)
            let maskRead = Date().addingTimeInterval(10)
            while index.isPreparing(page), Date() < maskRead { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(index.isReady(page))
            model.chooseTool(.marker); XCTAssertTrue(model.markerWordsActive)
            await model.performUndo()
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, fullInk))
            XCTAssertFalse(index.isReady(page), "Ripristinare parti della penna deve invalidare l’OCR anche se le date dei tratti sono identiche.")
            XCTAssertFalse(model.markerWordsActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
        }
    }
    @MainActor func testTypedWordsUseLensSelectionRepeatCancelEmptyStrokeAndOneUndoWithoutRawInk() async throws {
        try await fixture { model in
            var text = TextElement(text: "Energia conservata\nSeconda riga")
            text.x = 60; text.y = 100; text.width = 400; text.fontSize = 24
            model.page?.texts = [text]; model.history.clear()
            model.chooseTool(.marker)
            let page = try XCTUnwrap(model.page), groups = PageWordIndex.shared.groups(for: page)
            let word = try XCTUnwrap(groups.first?.first)
            let trace = [CGPoint(x: word.rect.minX + 2, y: word.rect.maxY + 2), CGPoint(x: word.rect.maxX - 2, y: word.rect.maxY + 2)]
            let lens = try XCTUnwrap(PageWords.selection(trace: trace, groups: groups))
            XCTAssertEqual(lens.indices, [0]); XCTAssertEqual(PageWords.text(lens.indices, in: lens.words), "Energia")
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let first = try XCTUnwrap(MarkerWordSession(host: host, model: model)); first.move(trace); first.finish(cancelled: false)
            let marks = try XCTUnwrap(model.page?.pdfMarkups); XCTAssertEqual(marks.map(\.text), ["Energia"])
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertTrue(model.canUndo)
            let duplicate = try XCTUnwrap(MarkerWordSession(host: host, model: model)); duplicate.move(trace); duplicate.finish(cancelled: false)
            XCTAssertEqual(model.page?.pdfMarkups, marks)
            let empty = try XCTUnwrap(MarkerWordSession(host: host, model: model)); empty.move([.init(x: 500, y: 600), .init(x: 550, y: 600)]); empty.finish(cancelled: false)
            let cancelled = try XCTUnwrap(MarkerWordSession(host: host, model: model)); cancelled.move(trace); cancelled.finish(cancelled: true)
            XCTAssertEqual(model.page?.pdfMarkups, marks); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo(); XCTAssertTrue(model.page?.pdfMarkups?.isEmpty ?? true); XCTAssertFalse(model.canUndo)
            await model.performRedo(); XCTAssertEqual(model.page?.pdfMarkups, marks)
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page)); XCTAssertEqual(model.page?.pdfMarkups, marks)
        }
    }
    @MainActor func testWordHighlightsRemainColoredOverPhotosAndSameStyleOverlapsDoNotDarken() async throws {
        try await fixture { model in
            let picture = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { item in UIColor.white.setFill(); item.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) }
            let file = try await model.workspace.storeImage(try XCTUnwrap(picture.pngData()))
            var page = try XCTUnwrap(model.page); page.paper = .plain
            var image = ImageElement(file: file, width: 200, height: 200); image.x = 0; image.y = 0; page.images = [image]
            let words = [PageWord(text: "Prima", rect: CGRect(x: 30, y: 30, width: 70, height: 20)),
                         PageWord(text: "Seconda", rect: CGRect(x: 65, y: 30, width: 70, height: 20))]
            page.pdfMarkups = try WordHighlights.appending(words: words, indices: [0, 1], to: [], color: .yellow, width: page.width, height: page.height)
            let rendered = DocumentServices.image(page: page, drawing: PKDrawing(), workspace: model.workspace)
            let a = try pixel(rendered, at: CGPoint(x: 45, y: 40)), overlap = try pixel(rendered, at: CGPoint(x: 80, y: 40))
            XCTAssertLessThan(a[2], a[0] - 20, "Il giallo deve vedersi sopra la foto opaca")
            for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(a[channel] - overlap[channel]), 1, "L’intersezione viene dipinta una volta sola") }
            let baseline = DocumentServices.image(page: page, drawing: PKDrawing(strokes: [stroke([.init(x: 35, y: 40), .init(x: 95, y: 40)])]), workspace: model.workspace)
            XCTAssertGreaterThan(blackPixels(baseline), 10)
        }
    }
    @MainActor private func pixel(_ image: UIImage, at point: CGPoint) throws -> [Int] {
        let source = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(source.width) / image.size.width
        let cropped = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 255, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes.map(Int.init)
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
    @MainActor func testNativeInkComparisonIgnoresContainerIdentityButDetectsMasksTransformsAndSeeds() {
        let pen = stroke([CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 80)])
        let original = PKDrawing(strokes: [pen])
        XCTAssertTrue(NativeInkComparison.equal(original, PKDrawing(strokes: [pen])))
        XCTAssertTrue(NativeInkComparison.equal(PKDrawing(), PKDrawing()))
        var transformed = pen; transformed.transform = CGAffineTransform(translationX: 2, y: 0)
        XCTAssertFalse(NativeInkComparison.equal(original, PKDrawing(strokes: [transformed])))
        var masked = pen; masked.mask = UIBezierPath(rect: CGRect(x: 10, y: 20, width: 20, height: 20))
        XCTAssertFalse(NativeInkComparison.equal(original, PKDrawing(strokes: [masked])))
        var randomized = pen; randomized.randomSeed = pen.randomSeed ^ 1
        XCTAssertFalse(NativeInkComparison.equal(original, PKDrawing(strokes: [randomized])))
        let marker = stroke([CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 80)], marker: true)
        XCTAssertTrue(NativeInkComparison.equal(original, PKDrawing(strokes: [pen, marker]), ignoringMarkers: true))
        XCTAssertFalse(NativeInkComparison.equal(original, PKDrawing(strokes: [pen, marker])))
    }
}
