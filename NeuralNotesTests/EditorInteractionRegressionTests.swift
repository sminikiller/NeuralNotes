import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class EditorInteractionRegressionTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, CanvasHost) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800); host.synchronizePage(); host.layoutIfNeeded()
        host.interaction = CanvasInteraction(host: host, model: model)
        host.drawingAssistant = CanvasDrawingAssistant(host: host, model: model); model.drawingAssistant = host.drawingAssistant
        do { try await body(model, host); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func ink() -> PKStroke {
        let controls = [CGPoint(x: 130, y: 150), CGPoint(x: 240, y: 180)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: .init(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
    }
    @MainActor func testDefaultLassoSelectsAllShapeKindsAndInkAndUsesOneStyleEditor() async throws {
        try await fixture { model, host in
            let shapes = ShapeKind.allCases.map { ShapeElement(kind: $0, x: 100, y: 100, width: 200, height: 180) }
            let locked = ShapeElement(kind: .triangle, x: 120, y: 120, width: 130, height: 130)
            model.page?.shapes = shapes + [locked]; model.page?.lockedObjects = [locked.id]
            model.installNativeInk(PKDrawing(strokes: [ink()]))
            let signatures = EditorInkSignatures.make(model.canvas.drawing)
            model.chooseTool(.lasso)
            XCTAssertEqual(model.tool, .objects); XCTAssertTrue(model.selectFreehand)
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            let points = [CGPoint(x: 80, y: 80), CGPoint(x: 330, y: 80), CGPoint(x: 330, y: 310), CGPoint(x: 80, y: 310)]
            let path = UIBezierPath(); path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            host.interaction?.selectDocumentArea(path, polygonPoints: points)
            XCTAssertEqual(model.selectedIDs, Set(shapes.map(\.id)))
            XCTAssertTrue(model.selectionIncludesInk); XCTAssertEqual(model.selectedStrokeIndices, [0])
            model.editSelection(); XCTAssertEqual(model.shapeStyleRequest, 1); XCTAssertEqual(model.objectEditorRequest, 0)
            var style = NeuralNotesCore.ShapeStyle(); style.color = .red; style.width = 9
            style.fill = .green; style.fillOpacity = 0.6; style.dash = .dotted; style.strokeOpacity = 0.8
            model.applyShapeStyleAndParameters(style, template: nil)
            XCTAssertTrue(model.selectedShapes.allSatisfy { $0.red == InkColor.red.red && $0.lineWidth == 9 && $0.fill == .green && $0.dash == .dotted })
            XCTAssertEqual(model.page?.shapes?.first { $0.id == locked.id }, locked)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, shapes + [locked])
            await model.performRedo(); XCTAssertEqual(model.page?.shapes?.first?.lineWidth, 9)
            XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), signatures)
        }
    }
    @MainActor func testOpeningGuideOptionsNeverTogglesItOffAndKeepsBothSquaresIndependent() async throws {
        try await fixture { model, host in
            let guide = RulerGuideView(host: host, model: model); host.rulerGuide = guide
            for tool in [WorkspaceTool.ruler, .square45, .square60] {
                model.openToolOptions(tool); guide.update()
                XCTAssertTrue(model.rulerActive); XCTAssertEqual(model.rulerGuide.kind, tool.draftingKind)
                let length = model.rulerGuide.length
                model.openToolOptions(tool); XCTAssertTrue(model.rulerActive)
                XCTAssertEqual(model.rulerGuide.length, length)
                guide.accessibilityIncrement(); XCTAssertGreaterThan(model.rulerGuide.length, length)
                guide.accessibilityDecrement(); XCTAssertEqual(model.rulerGuide.length, length, accuracy: 0.001)
                XCTAssertFalse(guide.isUserInteractionEnabled)
                XCTAssertTrue(host.gestureRecognizers?.contains { ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 1 && $0.isEnabled } == true)
            }
            model.openToolOptions(.protractor); model.openToolOptions(.protractor)
            XCTAssertTrue(model.protractorActive); XCTAssertFalse(model.rulerActive)
        }
    }
    @MainActor func testSquareStrokeKeepsChosenEdgeWhenPencilMovesAwayAndUndoesOnce() async throws {
        try await fixture { model, host in
            model.chooseTool(.square60)
            model.rulerGuide.x = 380; model.rulerGuide.y = 500; model.rulerGuide.length = 250
            let corners = model.rulerGuide.vertices, a = corners[1], b = corners[2]
            let start = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let assistant = try XCTUnwrap(host.drawingAssistant)
            assistant.begin(at: start); assistant.move(samples: [.init(x: 100, y: 100), .init(x: 650, y: 900)])
            assistant.end(cancelled: false)
            let stroke = try XCTUnwrap(model.canvas.drawing.strokes.first)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            for point in stroke.path {
                let cross = (Double(point.location.x) - a.x) * (b.y - a.y) - (Double(point.location.y) - a.y) * (b.x - a.x)
                XCTAssertEqual(cross, 0, accuracy: 0.001)
            }
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }
    @MainActor func testBlankPageImmediatelyHidesOldNativeInkAndNewWritingMakesItVisible() async throws {
        try await fixture { model, host in
            model.page?.paper = .plain
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [ink()]); model.strokeEnded(); model.finishInkGesture()
            host.synchronizePage(); XCTAssertEqual(model.canvas.layer.opacity, 1)
            let old = try XCTUnwrap(model.page)
            await model.addPage()
            XCTAssertNotEqual(model.page?.id, old.id); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertEqual(model.canvas.layer.opacity, 0, "The native empty layer must never display an old PencilKit tile")
            XCTAssertEqual(host.surface.page.id, model.page?.id)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [ink()]); model.drawingChanged(); model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.layer.opacity, 1); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let savedOld = try await model.workspace.pageSnapshot(old.id)
            let original = try await model.workspace.drawing(savedOld)
            XCTAssertEqual(try PKDrawing(data: XCTUnwrap(original)).strokes.count, 1)
        }
    }
    @MainActor func testFreehandMarkerShowsItsFootprintBeforeLiftAndUsesWordOpacityAtEveryWidth() async throws {
        try await fixture { model, host in
            model.chooseTool(.marker); model.editWriting { $0.markerSnapWords = false }; model.editShapePreferences { $0.mode = .off }
            for width in [1.0, 12, 60] {
                model.chooseMarkerWidth(width)
                XCTAssertTrue(model.markerCustomInput); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
                let session = try XCTUnwrap(MarkerWordSession(host: host, model: model))
                session.move([CGPoint(x: 100, y: 200), CGPoint(x: 260, y: 200)])
                let preview = try XCTUnwrap(host.subviews.compactMap { $0 as? LiveMarkerPreview }.first)
                XCTAssertFalse(preview.isHidden)
                preview.layer.displayIfNeeded()
                XCTAssertNotNil(preview.layer.contents, "The marker must be drawn while the Pencil is still down")
                session.finish(cancelled: false)
                let stroke = try XCTUnwrap(model.canvas.drawing.strokes.last)
                XCTAssertTrue(stroke.path.allSatisfy { abs($0.opacity - 0.25) < 0.0001 && abs($0.size.width - width) < 0.001 })
                XCTAssertFalse(host.subviews.contains { $0 is LiveMarkerPreview })
                await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            }
        }
    }
}
