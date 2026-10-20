import XCTest
import UIKit
import PencilKit
import PDFKit
import PhotosUI
import NeuralNotesCore
@testable import NeuralNotes

final class EditorReliabilityTests: XCTestCase {
    @MainActor func testPageImageAndMarkdownExportKeepContentAndDoNotChangeNotebook() async throws {
        try await fixture { model in
            model.editText([TextElement(text: "Appunto esportabile")]); _ = await model.flush()
            let original = try await model.workspace.pages()
            let png = try model.exportPageImage(), jpeg = try model.exportPageImage(jpeg: true)
            let markdown = try await model.exportNotebookText()
            defer { for file in [png, jpeg, markdown] { try? FileManager.default.removeItem(at: file) } }
            XCTAssertNotNil(UIImage(contentsOfFile: png.path)); XCTAssertNotNil(UIImage(contentsOfFile: jpeg.path))
            XCTAssertTrue(try String(contentsOf: markdown, encoding: .utf8).contains("Appunto esportabile"))
            let after = try await model.workspace.pages(); XCTAssertEqual(original, after)
        }
    }
    @MainActor func testSelectionWidthKeepsOtherStrokesAndSupportsUndo() async throws {
        try await fixture { model in
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke(.pen), stroke(.marker)]); model.strokeEnded(); model.finishInkGesture()
            let second = model.canvas.drawing.strokes[1].path[0].size
            model.chooseTool(.objects); model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            model.changeSelectionWidth(3)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].size.width, 3, accuracy: 0.01)
            XCTAssertEqual(model.canvas.drawing.strokes[1].path[0].size, second)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].size.width, 12, accuracy: 0.01)
        }
    }
    @MainActor func testStudyTapeStickyNotesAndLocksSurviveUndoAndPageDuplication() async throws {
        try await fixture { model in
            model.addStickyNote("Definizione")
            let note = try XCTUnwrap(model.page?.texts.first)
            XCTAssertNotNil(note.background)
            model.arrangeSelection(front: true); XCTAssertTrue(model.page?.aboveInkObjects?.contains(note.id) == true)
            model.lockSelection(); model.selectAll(); XCTAssertFalse(model.selectedIDs.contains(note.id))
            model.unlockObjects(); model.selectedObjectID = nil
            model.addStudyTape(); let tape = try XCTUnwrap(model.page?.tapes?.first)
            model.toggleTape(tape.id); XCTAssertTrue(model.page?.tapes?.first?.revealed == true)
            await model.performUndo(); XCTAssertFalse(model.page?.tapes?.first?.revealed ?? true)
            let saved = await model.flush(); XCTAssertTrue(saved)
            let copy = try await model.workspace.duplicatePage(try XCTUnwrap(model.page?.id))
            XCTAssertNotEqual(copy.texts.first?.id, note.id); XCTAssertNotEqual(copy.tapes?.first?.id, tape.id)
            XCTAssertEqual(copy.aboveInkObjects?.first, copy.texts.first?.id)
            XCTAssertNoThrow(try NativePackageInspector.inspect(model.workspace.package))
        }
    }
    @MainActor func testListReturnKeepsFormattingAndEndsAnEmptyItem() {
        let view = UITextView(); view.attributedText = NSAttributedString(string: "1. Primo", attributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        view.typingAttributes = [.font: UIFont.boldSystemFont(ofSize: 24)]
        var changes = 0; let commands = TextFormatting(view: view) { changes += 1 }
        XCTAssertTrue(commands.replaceNewline(in: NSRange(location: view.text.utf16.count, length: 0), replacement: "\n"))
        XCTAssertEqual(view.text, "1. Primo\n2. ")
        XCTAssertTrue(commands.replaceNewline(in: NSRange(location: view.text.utf16.count, length: 0), replacement: "\n"))
        XCTAssertEqual(view.text, "1. Primo\n"); XCTAssertEqual(changes, 2)
        let font = view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }
    @MainActor func testChecklistCanBeToggledWithoutEnteringTextModeAndUndone() async throws {
        try await fixture { model in
            var text = TextElement(text: "☐ Attività"); text.x = 50; text.y = 60
            model.editText([text]); model.chooseTool(.pen)
            XCTAssertTrue(model.toggleChecklist(at: CGPoint(x: 56, y: 75)))
            XCTAssertEqual(model.page?.texts.first?.text, "☑ Attività")
            await model.performUndo(); XCTAssertEqual(model.page?.texts.first?.text, "☐ Attività")
        }
    }
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model) } catch { _ = await model.close(); throw error }; _ = await model.close()
    }
    @MainActor private func stroke(_ kind: PKInkingTool.InkType) -> PKStroke {
        let points = [CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)].enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i), size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(kind, color: kind == .marker ? .yellow : .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
    @MainActor func testPencilTextInputIsTransparentOverPaperAndPDF() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model
            let input = CanvasTextInput(host: host, model: model); host.textInput = input
            model.chooseTool(.text); model.beginTextEdit(at: CGPoint(x: 50, y: 60)); host.surface.page = try XCTUnwrap(model.page)
            input.refresh()
            XCTAssertFalse(input.view.isOpaque); XCTAssertEqual(input.view.backgroundColor, .clear); XCTAssertEqual(input.view.layer.borderWidth, 0)
            model.page?.pdfFile = "attachments/test.pdf"; input.refresh()
            XCTAssertEqual(input.view.backgroundColor, .clear)
        }
    }
    @MainActor func testPDFImportAfterUnsavedInkNeverCopiesInkOrTextToImportedPages() async throws {
        try await fixture { model in
            let original = try XCTUnwrap(model.page?.id)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke(.pen)]); model.strokeEnded()
            model.editText([TextElement(text: "Appunti della pagina precedente")])
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { renderer in
                for _ in 0..<3 { renderer.beginPage(); ("Pagina PDF" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
            }
            try data.write(to: file); await model.importPages(from: file)
            XCTAssertNil(model.error); XCTAssertNotEqual(model.page?.id, original); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertTrue(model.page?.texts.isEmpty == true); XCTAssertEqual(model.pages.count, 4)
            let imported = model.pages.filter { $0.id != original }
            for page in imported {
                let bytes = try await model.workspace.drawing(page)
                XCTAssertNil(bytes); XCTAssertTrue(page.texts.isEmpty); XCTAssertTrue(page.images.isEmpty)
            }
            let templateSaved = await model.useCurrentPDFAsTemplate(); XCTAssertTrue(templateSaved)
            await model.addPage()
            XCTAssertEqual(model.page?.pdfFile, imported.first?.pdfFile); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.select(try XCTUnwrap(model.pages.first(where: { $0.id == original })))
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1); XCTAssertEqual(model.page?.texts.first?.text, "Appunti della pagina precedente")
            await model.select(try XCTUnwrap(imported.first)); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testMarkerEraserShowsChangesDuringGestureAndCancelRestoresInk() async throws {
        try await fixture { model in
            model.canvas.drawing = PKDrawing(strokes: [stroke(.pen), stroke(.marker)])
            let original = model.canvas.drawing
            model.chooseTool(.eraser); model.editWriting { $0.markerOnly = true }
            let session = MarkerEraseSession(model: model); model.drawingShape = true
            session.append([StrokeSample(x: 140, y: 60), StrokeSample(x: 140, y: 100)])
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertNil(model.canvas.drawing.strokes[0].mask); XCTAssertNotNil(model.canvas.drawing.strokes[1].mask)
            XCTAssertFalse(model.dirty)
            session.finish(cancelled: true); model.drawingShape = false
            XCTAssertEqual(model.canvas.drawing.strokes.count, original.strokes.count); XCTAssertNil(model.canvas.drawing.strokes[1].mask)
        }
    }
    @MainActor func testPhotoPickerCancellationIsAnExplicitEmptyResult() {
        var finished = false
        let picker = PhotoLibraryImport { result in
            finished = true
            switch result { case .success(let data): XCTAssertNil(data); case .failure(let error): XCTFail(error.localizedDescription) }
        }
        let coordinator = picker.makeCoordinator()
        coordinator.picker(PHPickerViewController(configuration: PHPickerConfiguration()), didFinishPicking: [])
        XCTAssertTrue(finished)
    }
}
