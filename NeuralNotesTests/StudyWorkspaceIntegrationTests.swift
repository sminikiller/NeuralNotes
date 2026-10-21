import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class StudyWorkspaceIntegrationTests: XCTestCase {
    @MainActor func testExactTextLensRequestPreservesNotesAndCustomEditMenuHandlesRanges() async throws {
        try await fixture { model in
            model.editText([TextElement(text: "Energia e quantità")]); model.chooseTool(.text)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            let input = CanvasTextInput(host: host, model: model); host.textInput = input
            input.view.text = "Energia e quantità"
            let menu = input.textView(input.view, editMenuForTextIn: NSRange(location: 0, length: 7), suggestedActions: [])
            XCTAssertEqual((menu?.children.first as? UIAction)?.title, "Apri nella Lente AI")
            XCTAssertNil(input.textView(input.view, editMenuForTextIn: NSRange(location: Int.max, length: 7), suggestedActions: []))
            let texts = model.page?.texts, bytes = model.canvas.drawing.dataRepresentation()
            model.requestLens(text: "Energia", compact: true)
            XCTAssertEqual(model.lensTextSelection, "Energia"); XCTAssertTrue(model.lensPrefersPopup)
            XCTAssertEqual(model.page?.texts, texts); XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            model.requestLens(area: CGRect(x: 1, y: 1, width: 20, height: 30))
            XCTAssertNil(model.lensTextSelection); XCTAssertFalse(model.lensPrefersPopup)
        }
    }
    @MainActor func testCutImageClipboardSurvivesRemovalOfTheSourceMedia() async throws {
        try await fixture { model in
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
            let bytes = try XCTUnwrap(image.pngData()), file = try await model.workspace.storeImage(bytes)
            let element = ImageElement(file: file, width: 80, height: 80)
            model.addImage(element); model.cutSelection()
            XCTAssertTrue(model.page?.images.isEmpty == true)
            try FileManager.default.removeItem(at: model.workspace.package.appendingPathComponent(file))
            await model.pasteSelection()
            let pasted = try XCTUnwrap(model.page?.images.first)
            XCTAssertNotEqual(pasted.file, file)
            XCTAssertEqual(try Data(contentsOf: model.workspace.package.appendingPathComponent(pasted.file)), bytes)
        }
    }
    @MainActor func testEmbeddedRoadmapChecksUseIsolatedDocuments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await RoadmapDiagnostics.pageBatch(root: root.appendingPathComponent("batch"))
        try await RoadmapDiagnostics.quiz(root: root.appendingPathComponent("quiz"))
        try RoadmapDiagnostics.sourcesAndMaps()
        try await RoadmapDiagnostics.editor(root: root.appendingPathComponent("editor"))
        try await RoadmapDiagnostics.audioExportAndOrganization(root: root.appendingPathComponent("audio"))
        try RoadmapDiagnostics.lensAndWebLinks()
    }
    @MainActor func testWebAnswerInsertionPersistsClickableSourcesAndCanBeUndone() async throws {
        try await fixture { model in
            let source = WebSource(title: "Fonte", url: "https://example.com/fonte", endIndex: 4)
            let artifact = AIArtifact(text: "Dato", references: [], provider: "fixture · web", webSources: [source])
            XCTAssertTrue(model.insertAIAnswer(artifact))
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let pages = try await model.workspace.pages(), text = try XCTUnwrap(pages.first?.texts.first)
            XCTAssertTrue(text.text.contains(source.url))
            let value = RichText.attributed(text); var found = false
            value.enumerateAttribute(.link, in: NSRange(location: 0, length: value.length)) { link, _, _ in if (link as? URL)?.absoluteString == source.url { found = true } }
            XCTAssertTrue(found)
            await model.performUndo(); XCTAssertTrue(model.page?.texts.isEmpty == true)
        }
    }
    @MainActor func testSearchLocatesFormattedRotatedTextAndLaserNeverChangesDrawing() async throws {
        let value = NSMutableAttributedString(string: "Energia e quantità", attributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        var text = TextElement(text: value.string); text.rtf = RichText.data(value); text.rotation = 20
        let boxes = RichText.matchingRects("QUANTITA", in: text, pageHeight: 1024)
        XCTAssertFalse(boxes.isEmpty); XCTAssertTrue(boxes.allSatisfy { !$0.isEmpty && !$0.isNull })
        XCTAssertTrue(RichText.matchingRects("inesistente", in: text, pageHeight: 1024).isEmpty)
        try await fixture { model in
            let bytes = model.canvas.drawing.dataRepresentation()
            model.setLaserActive(true); XCTAssertTrue(model.laserActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            model.chooseTool(.pen); XCTAssertFalse(model.laserActive); XCTAssertTrue(model.canvas.drawingGestureRecognizer.isEnabled)
        }
    }
    @MainActor func testFailedCutRetainsAllOriginalInkAndObjects() async throws {
        try await fixture { model in
            model.editText([TextElement(text: "Non perdere")]); model.strokeBegan()
            model.canvas.drawing = PKDrawing(strokes: [stroke()]); model.strokeEnded(); model.finishInkGesture(); model.selectAll()
            let before = model.canvas.drawing.dataRepresentation(), texts = model.page?.texts
            model.cutSelection(maximumBytes: 1)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), before); XCTAssertEqual(model.page?.texts, texts); XCTAssertNotNil(model.error)
        }
    }
    @MainActor func testSelectionMoveHasOneUndoAndKeepsAudioAnchorsWithRepeatedCreationDates() async throws {
        try await fixture { model in
            let sourceID = try XCTUnwrap(model.page?.id), ink = stroke()
            let second = PKStroke(ink: ink.ink, path: ink.path, transform: CGAffineTransform(translationX: 0, y: 30))
            let note = TextElement(text: "Trasferisci")
            model.editText([note]); model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [ink, second]); model.strokeEnded(); model.finishInkGesture()
            var session = AudioSession(title: "Fonte")
            var segment = AudioTimelineSegment(file: "audio/move.caf", start: 0, hostStart: 0); segment.duration = 10; session.segments = [segment]
            let file = try await model.workspace.url(segment.file); try Data([1]).write(to: file); try await model.workspace.saveSession(session)
            let signatures = EditorInkSignatures.make(model.canvas.drawing)
            model.page?.anchors = [StrokeAnchor(signature: signatures[0], audioSessionID: session.id, seconds: 1), StrokeAnchor(signature: signatures[1], audioSessionID: session.id, seconds: 2)]
            model.drawingChanged(); await model.addPage(); let destinationID = try XCTUnwrap(model.page?.id)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [ink]); model.strokeEnded(); model.finishInkGesture()
            let source = try await model.workspace.pageSnapshot(sourceID); await model.select(source)
            model.selectedIDs = [note.id]; model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            await model.moveSelection(to: destinationID)
            XCTAssertEqual(model.page?.id, destinationID); XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            XCTAssertEqual(model.page?.texts.first?.text, note.text); XCTAssertEqual(model.page?.anchors.first?.seconds, 1)
            XCTAssertEqual(model.page?.anchors.first?.signature, EditorInkSignatures.make(model.canvas.drawing)[1])
            let remaining = try await model.workspace.pageSnapshot(sourceID)
            XCTAssertTrue(remaining.texts.isEmpty); XCTAssertEqual(remaining.anchors.first?.seconds, 2)
            await model.performUndo(); XCTAssertEqual(model.page?.id, sourceID); XCTAssertEqual(model.canvas.drawing.strokes.count, 2); XCTAssertEqual(model.page?.texts, [note])
            await model.performRedo(); XCTAssertEqual(model.page?.id, destinationID); XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
        }
    }
    @MainActor func testPDFDropImportsFreshPagesAndPreservesOriginalNotes() async throws {
        try await fixture { model in
            model.editText([TextElement(text: "Originale da conservare")]); let original = try XCTUnwrap(model.page?.id)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf"); defer { try? FileManager.default.removeItem(at: file) }
            try pdf().write(to: file)
            let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))
            await PageDrop.insert([provider], at: CGPoint(x: 50, y: 50), model: model)
            XCTAssertEqual(model.pages.count, 2); XCTAssertNotNil(model.page?.pdfFile); XCTAssertTrue(model.page?.texts.isEmpty == true)
            let retained = try await model.workspace.pageSnapshot(original); XCTAssertEqual(retained.texts.first?.text, "Originale da conservare")
        }
    }
    @MainActor func testFollowingPageSourceFlushesPendingInkAndSupportsUndoOfLinkInsertion() async throws {
        try await fixture { model in
            let origin = try XCTUnwrap(model.page)
            await model.addPage(); let target = try XCTUnwrap(model.page)
            await model.select(origin)
            var text = TextElement(text: "↗ Fonte PDF")
            text.pageLink = PageLinkTarget(documentID: model.workspace.documentID, pageID: target.id)
            model.mutatePage("Collegamento") { $0.texts.append(text) }
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke()]); model.strokeEnded(); model.finishInkGesture()
            await model.openPageLink(try XCTUnwrap(text.pageLink))
            XCTAssertEqual(model.page?.id, target.id); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            let stored = try await model.workspace.pageSnapshot(origin.id)
            XCTAssertEqual(stored.texts.first?.pageLink, text.pageLink)
            let bytes = try await model.workspace.drawing(stored)
            XCTAssertEqual(try PKDrawing(data: XCTUnwrap(bytes)).strokes.count, 1)
            await model.openPageLink(PageLinkTarget(documentID: model.workspace.documentID, pageID: origin.id))
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 0)
            await model.performUndo(); XCTAssertTrue(model.page?.texts.isEmpty == true)
        }
    }
    @MainActor func testSectionMetadataKeepsUncommittedNotesOnTheirOriginalPage() async throws {
        try await fixture { model in
            let originalID = try XCTUnwrap(model.page?.id)
            model.editText([TextElement(text: "Da conservare")])
            let section = NotebookSection(title: "Esercizi")
            let created = await model.changeSections { try await $0.saveSection(section) }; XCTAssertTrue(created)
            let assigned = await model.changeSections { try await $0.assignPages([originalID], toSection: section.id) }; XCTAssertTrue(assigned)
            await model.addPage()
            XCTAssertTrue(model.page?.texts.isEmpty == true)
            let saved = try await model.workspace.pageSnapshot(originalID)
            XCTAssertEqual(saved.texts.first?.text, "Da conservare"); XCTAssertEqual(model.sections.first?.pageIDs, [originalID])
            let current = model.page?.id
            await model.openPageLink(PageLinkTarget(documentID: UUID(), pageID: originalID))
            XCTAssertEqual(model.page?.id, current); XCTAssertNotNil(model.error)
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
