import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class HandwritingSessionTests: XCTestCase {
    @MainActor func testBothWidthHandlesSupportVoiceOverAdjustmentWithoutEditingTheNativeDrawing() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
            host.surface.package = model.workspace.package; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 700, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
            let original = model.canvas.drawing
            model.beginHandwriting(.reflow); let session = try await self.ready(model)
            let handles = host.handwritingPreview.subviews
            let left = try XCTUnwrap(handles.first { $0.accessibilityIdentifier == "handwritingLeftHandle" })
            let right = try XCTUnwrap(handles.first { $0.accessibilityIdentifier == "handwritingRightHandle" })
            XCTAssertTrue(left.accessibilityTraits.contains(.adjustable)); XCTAssertTrue(right.accessibilityTraits.contains(.adjustable))
            let origin = session.left, width = session.width
            right.accessibilityIncrement(); _ = try await self.ready(model)
            XCTAssertEqual(session.width, width + 8, accuracy: 0.01)
            left.accessibilityIncrement(); _ = try await self.ready(model)
            XCTAssertEqual(session.left, origin + 8, accuracy: 0.01); XCTAssertEqual(session.width, width, accuracy: 0.01)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original)); XCTAssertFalse(model.dirty)
            model.cancelHandwriting()
        }
    }
    @MainActor func test030FixtureKeepsItsNativeHandwritingThroughRefinementReopenPDFAndBackupImport() async throws {
        try await fixture { model in
            let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tests/Fixtures/0.30.0/page.json")
            var legacy = try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: file))
            let current = try XCTUnwrap(model.page)
            legacy.id = current.id; legacy.revision = current.revision; legacy.layers?[0].id = current.id
            model.page = legacy; model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            model.tool = .objects; model.selectionIncludesInk = true; model.selectedStrokeIndices = nil
            let original = model.canvas.drawing
            model.beginHandwriting(.straighten); let preview = try await self.ready(model)
            preview.apply(); let refined = model.canvas.drawing
            XCTAssertFalse(NativeInkComparison.equal(refined, original))
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, refined))
            XCTAssertEqual(model.page?.recognizedText, legacy.recognizedText)
            let manifest = try await model.workspace.manifest()
            let notebook = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Grafia precedente",
                createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
            let backup = try await model.workspace.exportNative(metadata: notebook)
            defer { try? FileManager.default.removeItem(at: backup) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try NativeDocumentStore(root: root), documentID = UUID(), notebookID = UUID()
            _ = try NativeImport.copy(from: backup, into: store, documentID: documentID, notebookID: notebookID)
            let copy = DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
            let pages = try await copy.pages(), restored = try XCTUnwrap(pages.first)
            XCTAssertNotEqual(restored.id, current.id); XCTAssertEqual(restored.recognizedText, legacy.recognizedText)
            let native = try await LayerDrawingReader.read(page: restored, layerID: restored.id, workspace: copy)
            XCTAssertTrue(NativeInkComparison.equal(native.drawing, refined)); try PageValidation.validate(restored)
            let output = try await DocumentServices.exportPDF(workspace: copy)
            defer { try? FileManager.default.removeItem(at: output) }
            XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
            let pdf = try XCTUnwrap(CGPDFDocument(output as CFURL)), dictionary = try XCTUnwrap(pdf.page(at: 1)?.dictionary)
            XCTAssertFalse(PDFResourceProbe.hasImages(dictionary), "Refined native handwriting must remain vector in PDF export")
        }
    }
    @MainActor func testUndoDuringPreviewOnlyCancelsTheProposalAndLeavesThePreviousRealActionInHistory() async throws {
        try await fixture { model in
            let original = model.canvas.drawing, title = model.page?.title
            model.mutatePage("Titolo pagina") { $0.title = "Prima" }
            XCTAssertNotNil(model.history.undo)
            model.beginHandwriting(.straighten); _ = try await self.ready(model)
            await model.performUndo()
            XCTAssertNil(model.handwriting); XCTAssertEqual(model.page?.title, "Prima")
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original))
            XCTAssertNotNil(model.history.undo); XCTAssertNil(model.history.redo)
            await model.performUndo(); XCTAssertEqual(model.page?.title, title)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original))
        }
    }
    @MainActor func testWidthChangesCoalesceToTheLatestProposalAndACancelledSessionCannotRestart() async throws {
        try await fixture { model in
            let original = model.canvas.drawing
            model.beginHandwriting(.reflow); let session = try await self.ready(model)
            for offset in [20.0, 40.0, 80.0, 60.0] {
                session.width = session.minimumWidth + offset; session.recompute()
                try await Task.sleep(for: .milliseconds(10))
            }
            _ = try await self.ready(model)
            let input = try XCTUnwrap(session.input), header = try XCTUnwrap(model.page)
            var options = HandwritingOptions(); options.reflowX = session.left
            let expected = try HandwritingLayout.propose(.reflow(width: session.width), strokes: input.strokes,
                analysis: input.analysis, page: .init(x: 0, y: 0, width: header.width, height: header.height), options: options)
            XCTAssertEqual(session.proposal?.adjustments, expected.adjustments)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original)); XCTAssertFalse(model.dirty)
            model.cancelHandwriting()
            session.recompute(); session.apply()
            XCTAssertFalse(session.canApply); XCTAssertNil(model.handwriting)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original)); XCTAssertFalse(model.canUndo)
        }
    }
    @MainActor func testPreviewBlocksObjectDraggingAndCancelRestoresSelectionGestures() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
            host.surface.package = model.workspace.package; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 700, height: 500); host.setNeedsLayout(); host.layoutIfNeeded()
            let interaction = CanvasInteraction(host: host, model: model), gesture = UIPanGestureRecognizer()
            model.selectFreehand = true
            XCTAssertTrue(interaction.gestureRecognizerShouldBegin(gesture))
            let pinch = model.canvas.pinchGestureRecognizer?.isEnabled
            model.beginHandwriting(.straighten); _ = try await self.ready(model)
            XCTAssertFalse(interaction.gestureRecognizerShouldBegin(gesture))
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertEqual(model.canvas.pinchGestureRecognizer?.isEnabled, pinch)
            model.cancelHandwriting()
            XCTAssertTrue(interaction.gestureRecognizerShouldBegin(gesture))
        }
    }
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = try await workspace.addPage(); page.recognizedText = "Le parole originali non cambiano"; page.revision += 1
        var strokes: [PKStroke] = []
        for row in 0..<5 {
            let baseline: CGFloat = 100 + CGFloat(row) * 70
            let slope: CGFloat = CGFloat(row + 1) * 0.6
            var controls: [PKStrokePoint] = []
            for index in 0..<20 {
                let x: CGFloat = 80 + CGFloat(index) * 9
                let y: CGFloat = baseline + CGFloat(index) * slope
                let timeOffset: TimeInterval = Double(index) * 0.02
                let force: CGFloat = CGFloat(index % 7) / 8
                let point = PKStrokePoint(location: CGPoint(x: x, y: y),
                    timeOffset: timeOffset, size: CGSize(width: 4, height: 4), opacity: 1,
                    force: force, azimuth: 0.2, altitude: 1.1, secondaryScale: 0.75)
                controls.append(point)
            }
            strokes.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controls,
                creationDate: Date(timeIntervalSince1970: Double(1000 + row))), transform: .identity, mask: nil, randomSeed: UInt32(row + 20)))
        }
        _ = try await workspace.save(page, drawing: PKDrawing(strokes: strokes).dataRepresentation())
        let model = EditorViewModel(workspace: workspace); await model.open()
        model.tool = .objects; model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(strokes.indices)
        do { try await body(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func ready(_ model: EditorViewModel) async throws -> HandwritingSession {
        let session = try XCTUnwrap(model.handwriting)
        let deadline = Date().addingTimeInterval(10)
        while session.preparing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.preparing, "Await the proposal state rather than a guessed fixed delay")
        XCTAssertTrue(session.canApply, session.message ?? "No applicable preview")
        return session
    }
    @MainActor func testPreviewDoesNotSaveAndApplyIsOneUndoWithExactNativeRestorationAndUnchangedOCR() async throws {
        try await fixture { model in
            let original = model.canvas.drawing, header = try XCTUnwrap(model.page)
            XCTAssertFalse(model.canUndo); XCTAssertNil(model.history.undo); XCTAssertFalse(model.dirty)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            XCTAssertTrue(NativeInkComparison.equal(original, model.canvas.drawing)); XCTAssertEqual(model.page, header)
            XCTAssertTrue(model.canUndo); XCTAssertNil(model.history.undo); XCTAssertFalse(model.dirty)
            XCTAssertNotNil(session.preview); session.apply()
            XCTAssertNil(model.handwriting); XCTAssertTrue(model.canUndo)
            XCTAssertEqual(model.page?.recognizedText, header.recognizedText)
            let modified = model.canvas.drawing
            XCTAssertFalse(NativeInkComparison.equal(modified, original))
            XCTAssertEqual(EditorInkSignatures.make(modified), EditorInkSignatures.make(original))
            for stroke in modified.strokes {
                let first = try XCTUnwrap(stroke.path.first).location.applying(stroke.transform)
                let last = try XCTUnwrap(stroke.path.last).location.applying(stroke.transform)
                XCTAssertEqual(first.y, last.y, accuracy: 0.2, "Every synthetic line must actually be horizontal")
            }
            await model.performUndo()
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, original)); XCTAssertFalse(model.canUndo)
            XCTAssertEqual(model.page?.recognizedText, header.recognizedText)
            await model.performRedo(); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, modified))
        }
    }
    @MainActor func testCancelAndPageNavigationDiscardPreviewWithoutEditingOrSavingTheSource() async throws {
        try await fixture { model in
            let original = model.canvas.drawing, source = try XCTUnwrap(model.page)
            model.beginHandwriting(.cleanup); _ = try await self.ready(model)
            model.cancelHandwriting()
            XCTAssertTrue(NativeInkComparison.equal(original, model.canvas.drawing)); XCTAssertFalse(model.dirty); XCTAssertFalse(model.canUndo)
            model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(original.strokes.indices)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            let second = try await model.workspace.addPage()
            await model.select(second)
            XCTAssertNil(model.handwriting); XCTAssertEqual(model.page?.id, second.id); XCTAssertFalse(session.canApply)
            session.apply(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            let stored = try await model.workspace.pageSnapshot(source.id)
            XCTAssertEqual(stored.drawingFile, source.drawingFile); XCTAssertEqual(stored.recognizedText, source.recognizedText)
        }
    }
    @MainActor func testLayerOwnerAndItsOtherNativeArchiveRemainUnchangedUntilApplyAndThroughUndo() async throws {
        try await fixture { model in
            let base = model.canvas.drawing
            let original = try XCTUnwrap(model.page)
            let added = try PageLayerEditing.adding(to: original, name: "Grafia")
            var layered = added.page; layered.revision += 1
            layered = try await model.workspace.save(layered, drawing: base.dataRepresentation(), layerID: added.layerID)
            try await model.load(layered); await model.selectLayer(added.layerID)
            model.tool = .objects; model.selectionIncludesInk = true; model.selectedStrokeIndices = Set(base.strokes.indices)
            model.beginHandwriting(.straighten); let session = try await self.ready(model)
            session.apply(); XCTAssertEqual(model.drawingLayerID, added.layerID)
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let stored = try await model.workspace.pageSnapshot(original.id)
            let baseRead = try await LayerDrawingReader.read(page: stored, layerID: original.id, workspace: model.workspace)
            XCTAssertTrue(NativeInkComparison.equal(baseRead.drawing, base))
            await model.performUndo(); XCTAssertEqual(model.drawingLayerID, added.layerID)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, base))
        }
    }
}
