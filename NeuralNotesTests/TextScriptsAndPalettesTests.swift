import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class TextScriptsAndPalettesTests: XCTestCase {
    @MainActor func testScriptScalesEachRunAndTogglesWithoutLosingTraitsOrOtherFormatting() throws {
        let view = UITextView(), value = NSMutableAttributedString(string: "H2 x3", attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.blue])
        value.addAttributes([.font: UIFont.boldSystemFont(ofSize: 30), .underlineStyle: 1], range: NSRange(location: 3, length: 2))
        view.attributedText = value; view.selectedRange = NSRange(location: 0, length: value.length)
        let formatting = TextFormatting(view: view) {}
        formatting.superscript()
        XCTAssertEqual(try font(view, at: 0).pointSize, 12.6, accuracy: 0.01)
        XCTAssertEqual(try font(view, at: 3).pointSize, 21, accuracy: 0.01)
        XCTAssertTrue(try font(view, at: 3).fontDescriptor.symbolicTraits.contains(.traitBold))
        formatting.subscriptText()
        XCTAssertEqual(try font(view, at: 3).pointSize, 21, accuracy: 0.01)
        XCTAssertEqual((view.attributedText.attribute(.baselineOffset, at: 3, effectiveRange: nil) as? NSNumber)?.doubleValue, -6)
        formatting.subscriptText()
        XCTAssertEqual(try font(view, at: 0).pointSize, 18, accuracy: 0.01)
        XCTAssertEqual(try font(view, at: 3).pointSize, 30, accuracy: 0.01)
        XCTAssertEqual(view.attributedText.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(view.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .blue)
        XCTAssertEqual(view.text, value.string)
    }
    @MainActor func testRTFRoundTripKeepsTheExactBaseSizeAndLegacyOffsetsNeverInflateTheFont() throws {
        for size in [14.0, 18, 24, 26, 36] {
            let view = UITextView(); view.attributedText = NSAttributedString(string: "H2O", attributes: [.font: UIFont.systemFont(ofSize: size)])
            view.selectedRange = NSRange(location: 1, length: 1)
            let formatting = TextFormatting(view: view) {}; formatting.subscriptText()
            var text = TextElement(text: view.text); text.rtf = try XCTUnwrap(RichText.data(view.attributedText))
            XCTAssertTrue(String(decoding: text.rtf!, as: UTF8.self).contains("\\nnscript "))
            view.attributedText = RichText.attributed(text); view.selectedRange = NSRange(location: 1, length: 1)
            formatting.normalBaseline()
            XCTAssertEqual(try font(view, at: 1).pointSize, size, accuracy: 0.01, "Restore the saved base, not an inferred ratio")
            XCTAssertEqual(view.text, "H2O")
        }
        for offset in [8, -5] {
            let legacy = UITextView(); legacy.attributedText = NSAttributedString(string: "Legacy", attributes: [.font: UIFont.boldSystemFont(ofSize: 18), .baselineOffset: offset])
            legacy.selectedRange = NSRange(location: 0, length: 6)
            TextFormatting(view: legacy) {}.normalBaseline()
            XCTAssertEqual(try font(legacy, at: 0).pointSize, 18)
            XCTAssertTrue(try font(legacy, at: 0).fontDescriptor.symbolicTraits.contains(.traitBold))
            XCTAssertNil(legacy.attributedText.attribute(.baselineOffset, at: 0, effectiveRange: nil))
        }
    }
    @MainActor func testEmptySelectionChangesOnlyTypingAttributesAndSupportsScriptCycling() throws {
        let view = UITextView(); view.attributedText = NSAttributedString(string: "H", attributes: [.font: UIFont.systemFont(ofSize: 24)])
        view.selectedRange = NSRange(location: 1, length: 0); view.typingAttributes = [.font: UIFont.systemFont(ofSize: 24)]
        let formatting = TextFormatting(view: view) {}; formatting.superscript()
        XCTAssertEqual((view.typingAttributes[.font] as? UIFont)?.pointSize ?? 0, 16.8, accuracy: 0.01)
        XCTAssertEqual(try font(view, at: 0).pointSize, 24)
        formatting.subscriptText(); formatting.normalBaseline()
        XCTAssertEqual((view.typingAttributes[.font] as? UIFont)?.pointSize, 24)
    }
    @MainActor func testNativeCalligraphyAvailabilityUsesTheActualPencilKitInkOrSafeFallback() {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let tool = PKInkingTool(PenKind.reed.native, color: .black, width: 4)
            XCTAssertEqual(tool.inkType, .reed); XCTAssertTrue(PenKind.availableKinds.contains(.reed)); return
        }
        #endif
        XCTAssertFalse(PenKind.availableKinds.contains(.reed)); XCTAssertEqual(PenKind.reed.native, .pen)
    }
    @MainActor func testScriptsStaySmallAndAboveOrBelowTheirBaselineInTheActualExportedPDF() async throws {
        try await editorFixture { model in
            let view = UITextView(); view.attributedText = NSAttributedString(string: "H2O3", attributes: [.font: UIFont.systemFont(ofSize: 36)])
            let formatting = TextFormatting(view: view) {}
            view.selectedRange = NSRange(location: 1, length: 1); formatting.subscriptText()
            view.selectedRange = NSRange(location: 3, length: 1); formatting.superscript()
            var text = TextElement(text: view.text); text.fontSize = 36; text.x = 60; text.y = 100; text.width = 300
            text.rtf = try XCTUnwrap(RichText.data(view.attributedText)); model.editText([text])
            let saved = await model.flush(); XCTAssertTrue(saved)
            let file = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: file) }
            let page = try XCTUnwrap(PDFDocument(url: file)?.page(at: 0)), string = try XCTUnwrap(page.string) as NSString
            func box(_ character: String) throws -> CGRect {
                let range = string.range(of: character); XCTAssertNotEqual(range.location, NSNotFound)
                guard range.location != NSNotFound else { throw CocoaError(.fileReadCorruptFile) }
                return page.characterBounds(at: range.location)
            }
            let base = try box("H"), lower = try box("2"), upper = try box("3")
            XCTAssertGreaterThan(base.height, 10)
            XCTAssertLessThan(lower.height, base.height * 0.85); XCTAssertLessThan(upper.height, base.height * 0.85)
            // PDF text coordinates have their origin at the bottom left.
            XCTAssertLessThan(lower.midY, base.midY); XCTAssertGreaterThan(upper.midY, base.midY)
        }
    }
    @MainActor func testScriptToolbarUndoUpdatesAnAlreadyActiveFieldAndPreservesTheOriginalRTF() async throws {
        try await editorFixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800); host.synchronizePage(); host.layoutIfNeeded()
            let input = CanvasTextInput(host: host, model: model); host.textInput = input
            model.chooseTool(.text); model.beginTextEdit(at: .init(x: 80, y: 100)); input.refresh()
            input.view.attributedText = NSAttributedString(string: "H2O", attributes: [.font: UIFont.systemFont(ofSize: 24)])
            input.textViewDidChange(input.view); model.commitTextEdit()
            let before = try XCTUnwrap(model.page?.texts.first), id = try XCTUnwrap(model.editingTextID)
            input.view.selectedRange = NSRange(location: 1, length: 1); input.format(.subscriptText)
            XCTAssertEqual(try font(input.view, at: 1).pointSize, 16.8, accuracy: 0.01)
            await model.performUndo()
            XCTAssertEqual(model.editingTextID, id); XCTAssertFalse(input.view.isHidden)
            XCTAssertEqual(model.page?.texts.first?.rtf, before.rtf); XCTAssertEqual(try font(input.view, at: 1).pointSize, 24)
            await model.performRedo()
            XCTAssertEqual(model.editingTextID, id); XCTAssertEqual(try font(input.view, at: 1).pointSize, 17, accuracy: 0.6)
            input.view.selectedRange = NSRange(location: 1, length: 1); input.format(.normalBaseline)
            XCTAssertEqual(try font(input.view, at: 1).pointSize, 24, accuracy: 0.01)
        }
    }
    @MainActor func testSectionUndoChangesOnlySectionsAndKeepsLaterAudioCatalogUpdates() async throws {
        try await editorFixture { model in
            let section = NotebookSection(title: "Fisica")
            let changed = await model.changeSections { try await $0.saveSection(section) }; XCTAssertTrue(changed)
            let audio = AudioSession(title: "Lezione conservata")
            try await model.workspace.saveSession(audio)
            await model.performUndo(); XCTAssertTrue(model.sections.isEmpty)
            let afterUndo = try await model.workspace.catalog()
            XCTAssertEqual(afterUndo.sessions.map(\.id), [audio.id])
            await model.performRedo(); XCTAssertEqual(model.sections.map(\.id), [section.id])
            let afterRedo = try await model.workspace.catalog()
            XCTAssertEqual(afterRedo.sessions.map(\.id), [audio.id])
        }
    }
    @MainActor private func editorFixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model) } catch { _ = await model.close(); throw error }
        _ = await model.close()
    }
    @MainActor private func font(_ view: UITextView, at index: Int) throws -> UIFont {
        try XCTUnwrap(view.attributedText.attribute(.font, at: index, effectiveRange: nil) as? UIFont)
    }
}
