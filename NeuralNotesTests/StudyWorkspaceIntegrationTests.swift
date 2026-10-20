import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class StudyWorkspaceIntegrationTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model) } catch { _ = await model.close(); throw error }; _ = await model.close()
    }
    @MainActor private func stroke(_ kind: PKInkingTool.InkType = .pen) -> PKStroke {
        let points = [CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)].enumerated().map { index, at in
            PKStrokePoint(location: at, timeOffset: Double(index), size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: CGFloat.pi / 2)
        }
        return PKStroke(ink: PKInk(kind, color: kind == .marker ? .yellow : .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
    @MainActor private func pdf() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            context.beginPage(); ("Hello PDF study" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
    }
    @MainActor func testPDFCacheReusesImmutableSourcesAndCanBePurged() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf"); defer { try? FileManager.default.removeItem(at: file) }
        try pdf().write(to: file)
        let cache = DocumentRenderCache(), first = cache.pdf(file), second = cache.pdf(file)
        XCTAssertNotNil(first); XCTAssertTrue(first === second); XCTAssertEqual(cache.pdfOpens, 1)
        cache.clear(); XCTAssertNotNil(cache.pdf(file)); XCTAssertEqual(cache.pdfOpens, 2)
    }
    @MainActor func testZoomDetailIsBoundedToVisiblePaperAndDoesNotChangeInk() async throws {
        try await fixture { model in
            model.canvas.drawing = PKDrawing(strokes: [stroke()]); let before = model.canvas.drawing.dataRepresentation()
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.layoutIfNeeded()
            model.canvas.setZoomScale(4, animated: false); model.canvas.setContentOffset(CGPoint(x: 200, y: 300), animated: false); host.alignSurface()
            XCTAssertFalse(host.paperDetail.isHidden); XCTAssertTrue(host.bounds.contains(host.paperDetail.frame))
            let detail = host.paperDetail
            XCTAssertLessThanOrEqual(detail.bounds.width * detail.bounds.height * detail.contentScaleFactor * detail.contentScaleFactor, 8_000_001)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), before)
        }
    }
    @MainActor func testRichTextFormattingSurvivesSaveReloadAndPDFExport() async throws {
        try await fixture { model in
            let value = NSMutableAttributedString(string: "Importante appunto", attributes: [.font: UIFont.systemFont(ofSize: 24)])
            value.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 24), range: NSRange(location: 0, length: 10))
            value.addAttribute(.baselineOffset, value: 8, range: NSRange(location: 11, length: 7))
            var text = TextElement(text: value.string); text.rtf = RichText.data(value)
            model.editText([text]); let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            let restored = RichText.attributed(try XCTUnwrap(model.page?.texts.first))
            XCTAssertTrue(try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
            XCTAssertEqual(restored.attribute(.baselineOffset, at: 11, effectiveRange: nil) as? NSNumber, 8)
            let url = try await DocumentServices.exportPDF(workspace: model.workspace); defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(PDFDocument(url: url)?.string?.contains("Importante") == true)
        }
    }
    @MainActor func testFormattingCommandsAffectOnlyTheSelectionAndCreateChecklists() {
        let view = UITextView(); view.attributedText = NSAttributedString(string: "prima dopo", attributes: [.font: UIFont.systemFont(ofSize: 24)])
        var changes = 0; let commands = TextFormatting(view: view) { changes += 1 }
        view.selectedRange = NSRange(location: 0, length: 5); commands.bold()
        let first = view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let last = view.attributedText.attribute(.font, at: 7, effectiveRange: nil) as? UIFont
        XCTAssertTrue(first?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertFalse(last?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        commands.checklist(); XCTAssertTrue(view.text.hasPrefix("☐ ")); XCTAssertEqual(changes, 2)
    }
    @MainActor func testSelectionTransformsKeepUnselectedInkAndUndoNativeGeometry() async throws {
        try await fixture { model in
            let first = stroke(), second = stroke(.marker)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [first, second]); model.strokeEnded(); model.finishInkGesture()
            model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            model.transformSelection(scale: 1.2, degrees: 30)
            XCTAssertNotEqual(model.canvas.drawing.strokes[0].transform, first.transform)
            XCTAssertEqual(model.canvas.drawing.strokes[1].transform, second.transform)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path.creationDate, first.path.creationDate)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes[0].transform, first.transform)
            await model.performRedo(); XCTAssertNotEqual(model.canvas.drawing.strokes[0].transform, first.transform)
        }
    }
    @MainActor func testScratchOnRotatedRichTextPreservesTheRemainingWordsFormatting() throws {
        let value = NSMutableAttributedString(string: "prima dopo", attributes: [.font: UIFont.systemFont(ofSize: 24)])
        value.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 24), range: NSRange(location: 6, length: 4))
        var text = TextElement(text: value.string); text.x = 100; text.y = 100; text.width = 300; text.rotation = 30; text.rtf = RichText.data(value)
        let trace = CGPath(rect: CGRect(x: 95, y: 95, width: 70, height: 40), transform: nil)
        var rotation = RichText.rotation(text, pageHeight: 1024)
        let area = try XCTUnwrap(trace.copy(using: &rotation))
        let result = TextScratchEraser.eraseFormattedWords(text, in: area, pageHeight: 1024)
        XCTAssertEqual(result.text, "dopo"); XCTAssertEqual(result.rotation, 30)
        let font = RichText.attributed(result).attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }
    @MainActor func testMarkerOnlyEraserLeavesPenAndSupportsUndo() async throws {
        try await fixture { model in
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke(), stroke(.marker)]); model.strokeEnded(); model.finishInkGesture()
            model.chooseTool(.eraser); model.editWriting { $0.markerOnly = true }
            model.eraseMarkers(samples: [StrokeSample(x: 140, y: 60), StrokeSample(x: 140, y: 100)])
            XCTAssertNil(model.canvas.drawing.strokes[0].mask); XCTAssertNotNil(model.canvas.drawing.strokes[1].mask)
            await model.performUndo(); XCTAssertNil(model.canvas.drawing.strokes[1].mask)
            model.eraseMarkers(samples: [StrokeSample(x: 140, y: 80)])
            XCTAssertNil(model.canvas.drawing.strokes[0].mask); XCTAssertNotNil(model.canvas.drawing.strokes[1].mask)
            await model.performUndo()
            model.editWriting { $0.eraser = .stroke }
            model.eraseMarkers(samples: [StrokeSample(x: 140, y: 80)])
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1); XCTAssertEqual(model.canvas.drawing.strokes[0].ink.inkType, .pen)
            model.editWriting { $0.pen = .fountainPen }; model.chooseTool(.pen)
            XCTAssertEqual((model.canvas.tool as? PKInkingTool)?.inkType, .fountainPen)
        }
    }
    @MainActor func testPDFTextMarkupsPersistSeparatelyAndUndoPreservesTheOriginalPDF() async throws {
        try await fixture { model in
            let bytes = pdf(), input = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: input) }; try bytes.write(to: input)
            let imported = try await DocumentServices.importPDF(from: input, into: model.workspace)
            try await model.load(try XCTUnwrap(imported.first))
            let controller = PDFStudyController(), view = PDFView(); controller.attach(view)
            defer { controller.detach() }
            let file = try XCTUnwrap(model.page?.pdfFile); controller.load(file: file, package: model.workspace.package, index: 0)
            let source = try XCTUnwrap(view.document?.page(at: 0))
            view.currentSelection = source.selection(for: NSRange(location: 0, length: 5))
            let marks = controller.markups(kind: .highlight, pages: model.pages)
            XCTAssertFalse(marks.isEmpty); await model.addPDFMarkups(marks)
            XCTAssertFalse(model.page?.pdfMarkups?.isEmpty ?? true)
            XCTAssertEqual(try Data(contentsOf: model.workspace.package.appendingPathComponent(file)), bytes)
            await model.performUndo(); XCTAssertTrue(model.page?.pdfMarkups?.isEmpty ?? true)
            await model.performRedo(); XCTAssertFalse(model.page?.pdfMarkups?.isEmpty ?? true)
        }
    }
    @MainActor func testBlankPageInsertionIsBetweenExistingPagesAndUndoRestoresOrder() async throws {
        try await fixture { model in
            let first = try XCTUnwrap(model.page); await model.addPage(); await model.addPage()
            let order = model.pages.map(\.id); await model.select(first); await model.insertBlankPageAfterCurrent()
            XCTAssertEqual(model.pages.count, 4); XCTAssertEqual(model.pages[1].id, model.page?.id); XCTAssertNil(model.page?.pdfFile)
            await model.performUndo(); XCTAssertEqual(model.pages.map(\.id), order)
        }
    }
}
