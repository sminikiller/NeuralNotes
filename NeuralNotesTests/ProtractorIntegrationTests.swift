import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class ProtractorIntegrationTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, CanvasHost) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open(); model.chooseTool(.protractor)
        let host = CanvasHost(canvas: model.canvas); host.model = model
        host.frame = CGRect(x: 0, y: 0, width: 768, height: 1024); host.synchronizePage(); host.layoutIfNeeded()
        host.protractorGuide = ProtractorGuideView(host: host, model: model); host.protractorGuide?.update()
        model.protractorGuide = ProtractorGuide(x: 300, y: 400, radius: 140)
        host.protractorGuide?.update()
        do { try await body(model, host); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor func testArcStaysLatchedAwayFromTheBorderAndUndoesInOneStep() async throws {
        try await fixture { model, host in
            let session = try XCTUnwrap(ProtractorInkSession(host: host, model: model, start: .init(x: 440, y: 400)))
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            session.move([CGPoint(x: 380, y: 320), CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 200)])
            session.finish(cancelled: false)
            XCTAssertFalse(model.hasActiveStroke); XCTAssertFalse(model.protractorDrawing)
            let stroke = try XCTUnwrap(model.canvas.drawing.strokes.first)
            XCTAssertGreaterThan(stroke.path.count, 2)
            for point in stroke.path {
                XCTAssertEqual(hypot(point.location.x - 300, point.location.y - 400), 140, accuracy: 0.01)
            }
            let ink = model.canvas.drawing.dataRepresentation()
            XCTAssertTrue(model.canUndo); await model.performUndo()
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertFalse(model.canUndo)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.dataRepresentation(), ink)
        }
    }
    @MainActor func testRayAlwaysHasOneStraightDirectionAndRespectsThinMarkerWidth() async throws {
        try await fixture { model, host in
            model.chooseTool(.marker); model.chooseMarkerWidth(1)
            let session = try XCTUnwrap(ProtractorInkSession(host: host, model: model, start: .init(x: 300, y: 400)))
            session.move([CGPoint(x: 350, y: 380), CGPoint(x: 400, y: 300.4)])
            session.finish(cancelled: false)
            let stroke = try XCTUnwrap(model.canvas.drawing.strokes.first)
            XCTAssertEqual(stroke.path.count, 2); XCTAssertEqual(stroke.ink.inkType, .marker)
            XCTAssertEqual(stroke.path[0].location, CGPoint(x: 300, y: 400))
            XCTAssertEqual(stroke.path[1].location.x - 300, 400 - stroke.path[1].location.y, accuracy: 0.01)
            XCTAssertTrue(stroke.path.allSatisfy { $0.size.width == 1 && $0.size.height == 1 })
            XCTAssertEqual(model.guideReadout, "45°")
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testTwoMeasurementRaysMakeNoInkAndNoUndoEvent() async throws {
        try await fixture { model, host in
            model.protractorMeasure = true
            let before = model.canvas.drawing.dataRepresentation()
            for degrees in [15.0, 60] {
                let session = try XCTUnwrap(ProtractorInkSession(host: host, model: model, start: .init(x: 300, y: 400)))
                let point = try XCTUnwrap(model.protractorGuide.point(at: degrees * .pi / 180, distance: 120))
                session.move([CGPoint(x: point.x, y: point.y)]); session.finish(cancelled: false)
            }
            XCTAssertEqual(model.guideReadout, "Angolo 45°"); XCTAssertEqual(model.protractorRays.count, 2)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), before); XCTAssertFalse(model.canUndo)
            XCTAssertFalse(model.hasActiveStroke)
        }
    }
    @MainActor func testCancelledArcNeverReappearsInTheNextStrokeAndGuidesAreExclusive() async throws {
        try await fixture { model, host in
            let session = try XCTUnwrap(ProtractorInkSession(host: host, model: model, start: .init(x: 440, y: 400)))
            session.move([CGPoint(x: 300, y: 260)]); session.finish(cancelled: true)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertFalse(model.canUndo)
            model.chooseTool(.ruler); XCTAssertTrue(model.rulerActive); XCTAssertFalse(model.protractorActive)
            model.chooseTool(.protractor); XCTAssertFalse(model.rulerActive); XCTAssertTrue(model.protractorActive)
            let next = try XCTUnwrap(ProtractorInkSession(host: host, model: model, start: .init(x: 300, y: 400)))
            next.move([CGPoint(x: 410, y: 400)]); next.finish(cancelled: false)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path.count, 2)
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testVoiceOverCanResizeTheActualGuideWithoutEditingTheNotebook() async throws {
        try await fixture { model, host in
            let view = try XCTUnwrap(host.protractorGuide)
            XCTAssertLessThan(view.accessibilityFrameInContainerSpace.width, host.bounds.width)
            let radius = model.protractorGuide.radius
            view.accessibilityIncrement(); XCTAssertGreaterThan(model.protractorGuide.radius, radius)
            view.accessibilityDecrement(); XCTAssertEqual(model.protractorGuide.radius, radius, accuracy: 0.001)
            let move = try XCTUnwrap(view.accessibilityCustomActions?.first)
            // Each custom action has an explicit direction and is exposed to VoiceOver.
            XCTAssertEqual(move.name, "Sposta a sinistra")
            XCTAssertFalse(model.canUndo); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
}
