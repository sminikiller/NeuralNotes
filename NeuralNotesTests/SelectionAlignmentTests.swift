import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class SelectionAlignmentTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await run(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor func testAlignDistributeAndResizeUndoAsOneEditAndKeepLockedObjects() async throws {
        try await fixture { model in
            let shapes = [ShapeElement(kind: .rectangle, x: 80, y: 150, width: 40, height: 60),
                          ShapeElement(kind: .ellipse, x: 190, y: 210, width: 80, height: 90),
                          ShapeElement(kind: .star, x: 400, y: 400, width: 60, height: 60),
                          ShapeElement(kind: .diamond, x: 500, y: 500, width: 50, height: 50)]
            model.mutatePage("Fixture") { $0.shapes = shapes; $0.lockedObjects = [shapes[3].id] }
            model.selectedIDs = Set(shapes.map(\.id)); XCTAssertEqual(model.arrangementCount, 3)
            model.arrangeSelection(.top)
            XCTAssertEqual(model.page?.shapes?.prefix(3).map(\.y), [150, 150, 150])
            XCTAssertEqual(model.page?.shapes?[3], shapes[3])
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, shapes)
            await model.performRedo(); XCTAssertEqual(model.page?.shapes?.prefix(3).map(\.y), [150, 150, 150])
            // History intentionally clears selection; start the next command
            // with a fresh selection, exactly as the editor UI does.
            model.selectedIDs = Set(shapes.map(\.id))
            model.arrangeSelection(.horizontal)
            let result = try XCTUnwrap(model.page?.shapes)
            XCTAssertEqual(result[1].x - result[0].x - result[0].width, result[2].x - result[1].x - result[1].width, accuracy: 0.01)
            model.arrangeSelection(.width); XCTAssertEqual(model.page?.shapes?.prefix(3).map(\.width), [80, 80, 80])
            let saved = await model.flush(); XCTAssertTrue(saved)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
        }
    }
    @MainActor func testLassoInkMovesWithObjectsAndUndoRestoresOriginalSignatures() async throws {
        try await fixture { model in
            let points = (0...20).map { index in PKStrokePoint(location: CGPoint(x: Double(120 + index * 3), y: 300), timeOffset: Double(index) * 0.01,
                size: .init(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2) }
            model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: .init(controlPoints: points, creationDate: Date()))])
            let signatures = EditorInkSignatures.make(model.canvas.drawing)
            let originalBounds = model.canvas.drawing.bounds
            let anchor = StrokeAnchor(signature: try XCTUnwrap(signatures.first), audioSessionID: UUID(), seconds: 42)
            let shape = ShapeElement(kind: .rectangle, x: 60, y: 100, width: 100, height: 100)
            model.mutatePage("Fixture") { $0.shapes = [shape]; $0.anchors = [anchor] }
            model.selectedIDs = [shape.id]; model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            model.arrangeSelection(.top)
            XCTAssertEqual(model.selectedInkBounds.minY, 100, accuracy: 0.1)
            XCTAssertEqual(model.page?.anchors, [anchor])
            await model.performUndo(); XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), signatures)
            let restoredBounds = model.canvas.drawing.bounds
            XCTAssertEqual(restoredBounds.minX, originalBounds.minX, accuracy: 0.01)
            XCTAssertEqual(restoredBounds.minY, originalBounds.minY, accuracy: 0.01)
            XCTAssertEqual(restoredBounds.width, originalBounds.width, accuracy: 0.01)
            XCTAssertEqual(restoredBounds.height, originalBounds.height, accuracy: 0.01)
            XCTAssertEqual(model.page?.anchors, [anchor])
            await model.performRedo(); XCTAssertEqual(model.selectedInkBounds.minY, 100, accuracy: 0.1)
        }
    }
    @MainActor func testWorkspaceSnappingAndPreviousVersionFixtureSurviveBackupAndPDF() async throws {
        try await fixture { model in
            let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/0.25.0/page.json")
            var legacy = try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: file))
            let image = try await model.workspace.url("images/legacy.png")
            try Data(contentsOf: file.deletingLastPathComponent().appendingPathComponent("legacy.png")).write(to: image)
            legacy.id = try XCTUnwrap(model.page?.id); legacy.revision = model.page?.revision ?? 0
            model.page = legacy; model.drawingChanged()
            model.editSnapPreferences { $0.objects = false; $0.grid = true; $0.guides = false }
            let saved = await model.flush(); XCTAssertTrue(saved)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
            let manifest = try await model.workspace.manifest()
            let notebook = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Fixture 0.25", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
            let backup = try await model.workspace.exportNative(metadata: notebook)
            defer { try? FileManager.default.removeItem(at: backup) }
            XCTAssertGreaterThan(try Data(contentsOf: backup).count, 0)
            let restoredRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: restoredRoot) }
            let store = try NativeDocumentStore(root: restoredRoot), documentID = UUID(), notebookID = UUID()
            _ = try NativeImport.copy(from: backup, into: store, documentID: documentID, notebookID: notebookID)
            let copy = DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
            let restoredPages = try await copy.pages(), restored = try XCTUnwrap(restoredPages.first)
            let restoredCatalog = try await copy.catalog()
            XCTAssertEqual(restoredCatalog.editorWorkspaces?.selected.snapping, model.currentWorkspace.snapping)
            for (actual, original) in zip(restored.shapes ?? [], legacy.shapes ?? []) {
                var expected = original; expected.id = actual.id; XCTAssertEqual(actual, expected)
            }
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertEqual(model.page?.shapes, legacy.shapes)
            XCTAssertFalse(model.snapPreferences.objectsEnabled); XCTAssertEqual(model.snapPreferences.grid, true)
        }
    }
    @MainActor func testPastingMultipleShapesDoesNotOverlapPageAccessAndCanBeUndone() async throws {
        try await fixture { model in
            model.mutatePage("Fixture") { $0.shapes = [ShapeElement(kind: .star), ShapeElement(kind: .polygon, x: 300)] }
            model.selectedIDs = Set(model.page?.shapes?.map(\.id) ?? [])
            XCTAssertTrue(model.copySelection())
            await model.pasteSelection(); XCTAssertEqual(model.page?.shapes?.count, 4)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.count, 2)
        }
    }
    @MainActor func testMixedTextPhotoAndTapeAlignAndEqualHeightWithActualTextMetrics() async throws {
        try await fixture { model in
            var text = TextElement(text: "Testo breve"); text.x = 100; text.y = 200; text.width = 100; text.fontSize = 6
            var image = ImageElement(file: "images/fixture.png", width: 50, height: 70); image.x = 300; image.y = 300
            let tape = StudyTape(x: 400, y: 400, width: 80, height: 40)
            let imageURL = try await model.workspace.url(image.file)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let photo = UIGraphicsImageRenderer(size: .init(width: 8, height: 8), format: format).image { context in UIColor.red.setFill(); context.fill(.init(x: 0, y: 0, width: 8, height: 8)) }
            try XCTUnwrap(photo.pngData()).write(to: imageURL)
            model.mutatePage("Fixture") { $0.texts = [text]; $0.images = [image]; $0.tapes = [tape] }
            model.selectedIDs = [text.id, image.id, tape.id]
            let initial = model.page
            model.arrangeSelection(.top)
            XCTAssertEqual(model.page?.texts[0].y, 200); XCTAssertEqual(model.page?.images[0].y, 200); XCTAssertEqual(model.page?.tapes?[0].y, 200)
            await model.performUndo(); XCTAssertEqual(model.page?.texts, initial?.texts); XCTAssertEqual(model.page?.images, initial?.images)
            model.selectedIDs = [text.id, image.id, tape.id]; model.arrangeSelection(.height)
            let changed = try XCTUnwrap(model.page?.texts.first)
            XCTAssertEqual(RichText.bounds(changed, pageHeight: 1024).height, 70, accuracy: 0.25)
            XCTAssertEqual(model.page?.images[0].height, 70); XCTAssertEqual(model.page?.tapes?[0].height, 70)
            XCTAssertNotNil(changed.rtf)
            await model.performUndo(); XCTAssertEqual(model.page?.texts, initial?.texts)
        }
    }
    @MainActor func testSecondFingerModifiesAnActiveShapeButInitialTwoFingerGestureCanNavigate() async throws {
        try await fixture { model in
            model.chooseShape(.rectangle)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model); host.drawingAssistant = assistant
            assistant.begin(at: .init(x: 200, y: 200))
            XCTAssertFalse(assistant.additionalTouchIsModifier(primaryIsPencil: false))
            XCTAssertFalse(assistant.locksPageNavigation)
            assistant.cancel()
            assistant.begin(at: .init(x: 200, y: 200)); assistant.move(samples: [.init(x: 280, y: 300)])
            XCTAssertTrue(assistant.locksPageNavigation)
            XCTAssertFalse(model.canvas.panGestureRecognizer.isEnabled)
            XCTAssertTrue(assistant.additionalTouchIsModifier(primaryIsPencil: false))
            PaperInk.configureNavigation(model.canvas, fingerDrawing: true)
            XCTAssertFalse(model.canvas.panGestureRecognizer.isEnabled, "Un aggiornamento del layout non deve riattivare lo scorrimento durante il gesto.")
            assistant.end(cancelled: true)
            XCTAssertFalse(assistant.locksPageNavigation); XCTAssertTrue(model.canvas.panGestureRecognizer.isEnabled)
            XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            assistant.begin(at: .init(x: 220, y: 220))
            XCTAssertTrue(assistant.additionalTouchIsModifier(primaryIsPencil: true))
            assistant.cancel(); XCTAssertTrue(model.canvas.panGestureRecognizer.isEnabled)
        }
    }
    @MainActor func testPrimaryLiftWithModifierKeepsTheUnsnappedShapeEndpoint() async throws {
        try await fixture { model in
            model.chooseShape(.line)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.frame = .init(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model); host.drawingAssistant = assistant
            assistant.begin(at: .init(x: 100, y: 100)); assistant.move(samples: [.init(x: 300, y: 103)])
            assistant.end(cancelled: false, modifierActive: true)
            let shape = try XCTUnwrap(model.page?.shapes?.last)
            let end = try XCTUnwrap(ShapeHandles.positions(shape, zoom: 1).first { $0.0 == .end }?.1)
            XCTAssertEqual(end.x, 300, accuracy: 0.001); XCTAssertEqual(end.y, 103, accuracy: 0.001)
            XCTAssertFalse(assistant.locksPageNavigation); XCTAssertTrue(model.canvas.panGestureRecognizer.isEnabled)
            await model.performUndo(); XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
        }
    }
    @MainActor func testAccessibleRotationChangesAngleWithoutMovingTheShapeAndUndoesOnce() async throws {
        try await fixture { model in
            let shape = ShapeElement(kind: .star, x: 100, y: 100, width: 120, height: 120)
            model.mutatePage("Fixture") { $0.shapes = [shape] }; model.selectedObjectID = shape.id; model.chooseTool(.objects)
            let host = CanvasHost(canvas: model.canvas); host.model = model
            let handles = ShapeHandlesOverlay(host: host, model: model)
            XCTAssertTrue(handles.rotateByDegrees(15))
            XCTAssertEqual(model.page?.shapes?.first?.rotation, 15)
            XCTAssertEqual(model.page?.shapes?.first?.x, 100); XCTAssertEqual(model.page?.shapes?.first?.y, 100)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.first, shape)
            await model.performRedo(); XCTAssertEqual(model.page?.shapes?.first?.rotation, 15)
            model.selectedObjectID = shape.id
            XCTAssertTrue(handles.rotateByDegrees(-15)); XCTAssertEqual(model.page?.shapes?.first?.rotation, 0)
        }
    }
}
