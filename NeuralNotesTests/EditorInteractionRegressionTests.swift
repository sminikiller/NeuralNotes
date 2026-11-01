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
    @MainActor func testLassoTapSelectsTheInteriorOfUnfilledClosedShapesAndAnArcContour() async throws {
        try await fixture { model, host in
            model.chooseTool(.lasso)
            for kind in [ShapeKind.triangle, .rectangle, .ellipse, .polygon, .star, .freePolygon] {
                let shape = ShapeElement(kind: kind, x: 100, y: 100, width: 200, height: 200)
                model.page?.shapes = [shape]; model.selectedObjectID = nil
                XCTAssertEqual(host.interaction?.hit(CGPoint(x: 200, y: 200)), shape.id, "\(kind)")
            }
            var arc = ShapeElement(kind: .arc, x: 100, y: 100, width: 200, height: 200)
            arc.arcStart = 0; arc.arcSweep = .pi; model.page?.shapes = [arc]; model.selectedObjectID = nil
            let line = try XCTUnwrap(ShapeGeometry.polylines(ShapeGeometry.path(for: arc)).first)
            let at = line[line.count / 2]
            XCTAssertEqual(host.interaction?.hit(CGPoint(x: at.x, y: at.y)), arc.id)
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
                model.chooseTool(.objects); model.openToolOptions(tool)
                XCTAssertEqual(model.tool, .pen); XCTAssertTrue(model.rulerActive)
                XCTAssertFalse(guide.isUserInteractionEnabled)
                XCTAssertTrue(host.gestureRecognizers?.contains { ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 1 && $0.isEnabled } == true)
            }
            model.openToolOptions(.protractor); model.openToolOptions(.protractor)
            XCTAssertTrue(model.protractorActive); XCTAssertFalse(model.rulerActive)
            model.chooseTool(.objects); model.openToolOptions(.protractor)
            XCTAssertEqual(model.tool, .pen); XCTAssertTrue(model.protractorActive)
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
                // Cross products have square-point units. Assert the actual
                // perpendicular distance in page points after PK's Float storage.
                XCTAssertEqual(cross / hypot(b.x - a.x, b.y - a.y), 0, accuracy: 0.001)
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
            XCTAssertEqual(model.canvas.layer.opacity, 1)
            XCTAssertFalse(host.emptyInkCover.isHidden, "The current paper covers old tiles without hiding the touch responder")
            XCTAssertTrue(host.hitTest(CGPoint(x: 500, y: 400), with: nil)?.isDescendant(of: model.canvas) == true)
            XCTAssertEqual(host.surface.page.id, model.page?.id)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [ink()]); model.drawingChanged(); model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.layer.opacity, 1); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertTrue(host.emptyInkCover.isHidden)
            let savedOld = try await model.workspace.pageSnapshot(old.id)
            let original = try await model.workspace.drawing(savedOld)
            XCTAssertEqual(try PKDrawing(data: XCTUnwrap(original)).strokes.count, 1)
        }
    }
    @MainActor func testEmptyInkCoverHidesTheOriginalObjectDuringDragWithoutChangingStoredObjects() async throws {
        try await fixture { model, host in
            var shape = ShapeElement(kind: .rectangle, x: 100, y: 100, width: 200, height: 150)
            shape.fill = .red; shape.fillOpacity = 1; model.page?.paper = .plain; model.page?.shapes = [shape]
            host.synchronizePage(); host.layoutIfNeeded()
            @MainActor func redPixels() throws -> Int {
                host.emptyInkCover.layer.displayIfNeeded()
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: host.emptyInkCover.bounds.size, format: format).image { host.emptyInkCover.layer.render(in: $0.cgContext) }
                let source = try XCTUnwrap(image.cgImage)
                var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
                return try bytes.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                        bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                    let pixels = buffer.bindMemory(to: UInt8.self)
                    var count = 0
                    for i in stride(from: 0, to: pixels.count, by: 4) { if pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 { count += 1 } }
                    return count
                }
            }
            XCTAssertGreaterThan(try redPixels(), 100)
            host.surface.hiddenObjectID = shape.id
            XCTAssertEqual(try redPixels(), 0, "A drag must not leave the source image/shape underneath its moving preview")
            XCTAssertEqual(model.page?.shapes, [shape])
            host.surface.hiddenObjectID = nil; XCTAssertGreaterThan(try redPixels(), 100)
        }
    }
    @MainActor func testLiveMarkerKeepsAnObjectBroughtInFrontVisibleBeforeLift() async throws {
        try await fixture { model, host in
            model.chooseTool(.marker); model.editWriting { $0.markerSnapWords = false }; model.editShapePreferences { $0.mode = .off }
            var shape = ShapeElement(kind: .rectangle, x: 100, y: 150, width: 200, height: 100)
            shape.fill = .blue; shape.fillOpacity = 1
            model.page?.paper = .plain; model.page?.shapes = [shape]; model.page?.aboveInkObjects = [shape.id]
            host.synchronizePage(); host.layoutIfNeeded(); host.emptyInkCover.layer.displayIfNeeded(); host.foregroundObjects.layer.displayIfNeeded()
            @MainActor func bluePixels() throws -> Int {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: host.bounds.size, format: format).image { host.layer.render(in: $0.cgContext) }
                let source = try XCTUnwrap(image.cgImage)
                var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
                return try bytes.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                        bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                    let pixels = buffer.bindMemory(to: UInt8.self)
                    var count = 0
                    for i in stride(from: 0, to: pixels.count, by: 4) { if pixels[i] < 80 && pixels[i + 1] < 180 && pixels[i + 2] > 180 { count += 1 } }
                    return count
                }
            }
            let baseline = try bluePixels(); XCTAssertGreaterThan(baseline, 100)
            model.chooseMarkerWidth(60)
            let session = try XCTUnwrap(MarkerWordSession(host: host, model: model))
            session.move([CGPoint(x: 80, y: 200), CGPoint(x: 330, y: 200)])
            let preview = try XCTUnwrap(host.subviews.compactMap { $0 as? LiveMarkerPreview }.first)
            preview.layer.displayIfNeeded(); XCTAssertFalse(preview.isHidden)
            XCTAssertEqual(try bluePixels(), baseline, "Live marker must respect the same front-object order as saved ink")
            session.finish(cancelled: true)
            XCTAssertEqual(model.page?.aboveInkObjects, [shape.id]); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
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
