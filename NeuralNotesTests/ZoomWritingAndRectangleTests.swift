import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class ZoomWritingAndRectangleTests: XCTestCase {
    @MainActor private func fixture(_ test: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await test(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func stroke(x: CGFloat, y: CGFloat) -> PKStroke {
        let points = (0...8).map { i in PKStrokePoint(location: CGPoint(x: x + CGFloat(i) * 3, y: y), timeOffset: Double(i) * 0.01,
            size: CGSize(width: 3 + Double(i) / 4, height: 3), opacity: 0.9, force: 0.5 + CGFloat(i) / 20,
            azimuth: 0.3, altitude: 0.9) }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 900)))
    }
    @MainActor func testNativeChildWritesPageCoordinatesAndUndoThenNewStrokeNeverRevivesOldInk() async throws {
        try await fixture { model in
            model.zoomWritingOpen = true
            let controller = ZoomWritingController(model: model); controller.host.frame = CGRect(x: 0, y: 0, width: 700, height: 200)
            controller.resize(controller.host.bounds.size); controller.automatic = false
            let first = self.stroke(x: 90, y: 120)
            controller.canvasViewDidBeginUsingTool(controller.host.canvas)
            controller.host.canvas.drawing = PKDrawing(strokes: [first]); controller.completeNativeStroke()
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [first])))
            XCTAssertEqual(model.canvas.drawing.strokes[0].path[4].force, first.path[4].force)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path[4].azimuth, first.path[4].azimuth)
            XCTAssertTrue(model.canUndo)
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertTrue(controller.host.canvas.drawing.strokes.isEmpty)
            let next = self.stroke(x: 130, y: 160)
            controller.canvasViewDidBeginUsingTool(controller.host.canvas)
            controller.host.canvas.drawing = PKDrawing(strokes: [next]); controller.completeNativeStroke()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [next])))
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            controller.finishAndClose(); XCTAssertFalse(model.zoomWritingOpen)
        }
    }
    @MainActor func testStoppedReplayPreferenceDoesNotDisableTheWritingWindow() async throws {
        try await fixture { model in
            let audio = try XCTUnwrap(model.audio); audio.replayInk = true
            XCTAssertNil(audio.playingSessionID)
            model.toggleZoomWriting(); XCTAssertTrue(model.zoomWritingOpen)
            let controller = ZoomWritingController(model: model); controller.host.frame = CGRect(x: 0, y: 0, width: 700, height: 200)
            controller.resize(controller.host.bounds.size); XCTAssertTrue(model.zoomWritingOpen)
            audio.playingSessionID = UUID(); controller.configureTool()
            XCTAssertFalse(model.zoomWritingOpen); XCTAssertTrue(audio.replayInk)
            audio.stopPlayback(); model.toggleZoomWriting(); XCTAssertTrue(model.zoomWritingOpen)
            model.closeZoomWriting()
        }
    }
    @MainActor func testWritingWindowKeyboardPageFitTargetsTheAuthoritativeMainViewport() async throws {
        try await fixture { model in
            let parent = CanvasHost(canvas: model.canvas); parent.model = model; model.pagePresenter = parent
            parent.surface.page = try XCTUnwrap(model.page); parent.frame = CGRect(x: 0, y: 0, width: 1000, height: 700); parent.layoutIfNeeded()
            parent.togglePageZoom(animated: false); XCTAssertTrue(parent.fitsPageWidth)
            model.zoomWritingOpen = true
            let controller = ZoomWritingController(model: model); controller.host.frame = CGRect(x: 0, y: 0, width: 700, height: 200)
            controller.resize(controller.host.bounds.size)
            let command = UIKeyCommand(input: "0", modifierFlags: .command, action: #selector(CanvasHost.editorKey(_:)))
            controller.host.editorKey(command)
            XCTAssertFalse(parent.fitsPageWidth)
            XCTAssertEqual(controller.geometry?.zoom, 3)
            controller.finishAndClose()
        }
    }
    @MainActor func testLateNativeValueAndClosingDuringAMarkerPreserveDeliveredInk() async throws {
        try await fixture { model in
            model.zoomWritingOpen = true
            let controller = ZoomWritingController(model: model); controller.host.frame = CGRect(x: 0, y: 0, width: 700, height: 200)
            controller.resize(controller.host.bounds.size); controller.automatic = false
            controller.canvasViewDidBeginUsingTool(controller.host.canvas)
            controller.canvasViewDidEndUsingTool(controller.host.canvas) // final drawing arrives after this delegate callback
            let native = self.stroke(x: 100, y: 150)
            controller.host.canvas.drawing = PKDrawing(strokes: [native])
            let deadline = Date().addingTimeInterval(2)
            while model.hasActiveStroke && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(model.hasActiveStroke)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [native])))
            model.tool = .marker; model.editWriting { $0.markerMode = .freehand; $0.markerWidth = 2 }
            let assistant = try XCTUnwrap(controller.host.drawingAssistant)
            assistant.begin(at: CGPoint(x: 100, y: 180)); assistant.move(samples: [CGPoint(x: 200, y: 180)])
            XCTAssertTrue(model.hasActiveStroke)
            model.closeZoomWriting()
            XCTAssertFalse(model.hasActiveStroke); XCTAssertFalse(model.zoomWritingOpen)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            XCTAssertEqual(model.canvas.drawing.strokes.last?.ink.inkType, .marker)
            await model.performUndo()
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [native])))
        }
    }
    @MainActor func testRectangleIsEditableMultiplyAndMarkerOnlyEraserLeavesNormalShapeAndPen() async throws {
        try await fixture { model in
            model.tool = .marker; model.editWriting { $0.markerMode = .rectangle }
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = try XCTUnwrap(model.page)
            host.surface.package = model.workspace.package; host.frame = CGRect(x: 0, y: 0, width: 800, height: 700); host.layoutIfNeeded()
            model.ink = .yellow
            let session = try XCTUnwrap(RectangularMarkerSession(host: host, model: model, at: CGPoint(x: 80, y: 90)))
            session.move([CGPoint(x: 250, y: 140)]); session.finish(cancelled: false)
            let marker = try XCTUnwrap(model.page?.shapes?.first)
            XCTAssertEqual(marker.rectangularMarker, true); XCTAssertEqual(marker.strokeOpacity, 0)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo(); XCTAssertTrue(model.page?.shapes?.isEmpty != false)
            await model.performRedo(); XCTAssertEqual(model.page?.shapes?.first?.id, marker.id)
            model.addDraggedShape(.ellipse, from: .init(x: 300, y: 80), to: .init(x: 360, y: 140))
            let native = self.stroke(x: 100, y: 110); model.installNativeInk(PKDrawing(strokes: [native]))
            model.tool = .eraser; model.editWriting { $0.eraserTarget = .marker; $0.eraseObjects = false }
            let eraser = SelectiveEraseSession(model: model)
            eraser.append([.init(x: 150, y: 110)]); eraser.finish(cancelled: false)
            XCTAssertEqual(model.page?.shapes?.count, 1); XCTAssertEqual(model.page?.shapes?.first?.kind, .ellipse)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [native])))
        }
    }
    @MainActor func testRectangleMultiplyPreservesBlackContentAndMatchesTheMarkerColor() throws {
        var page = PageSnapshot(); page.width = 300; page.height = 250
        var printed = ShapeElement(kind: .rectangle, x: 100, y: 108, width: 50, height: 16)
        printed.fill = .black; printed.fillOpacity = 1; printed.strokeOpacity = 0
        let marker = try XCTUnwrap(RectangularMarker.make(CGRect(x: 80, y: 90, width: 120, height: 60), color: .yellow))
        page.shapes = [marker, printed] // The area stays above paper objects even when ordered earlier.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 250), format: format).image { target in
            PageRenderer.draw(page, package: URL(fileURLWithPath: "/"), in: target.cgContext)
        }
        let yellow = try pixel(image, point: CGPoint(x: 90, y: 100)), black = try pixel(image, point: CGPoint(x: 120, y: 115))
        XCTAssertGreaterThan(yellow[0], 245); XCTAssertGreaterThan(yellow[1], 245)
        XCTAssertLessThanOrEqual(abs(Int(yellow[2]) - 191), 3)
        XCTAssertLessThan(black[0], 10); XCTAssertLessThan(black[1], 10); XCTAssertLessThan(black[2], 10)
        let outline = ShapePathRendering.path(ShapeGeometry.path(for: marker))
        XCTAssertEqual(outline.boundingBoxOfPath, CGRect(x: 80, y: 90, width: 120, height: 60))
    }
    @MainActor private func pixel(_ image: UIImage, point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage), scale = image.scale
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
    @MainActor func testChildCustomMarkerAndPartialEraserHaveOneUndoAndKeepMainPaperSize() async throws {
        try await fixture { model in
            let parent = CanvasHost(canvas: model.canvas); parent.model = model; parent.surface.page = try XCTUnwrap(model.page)
            parent.frame = CGRect(x: 0, y: 0, width: 800, height: 600); parent.layoutIfNeeded()
            let pageSize = parent.surface.bounds.size
            model.zoomWritingOpen = true; model.pagePresenter = parent
            let controller = ZoomWritingController(model: model); controller.host.frame = CGRect(x: 0, y: 0, width: 700, height: 200)
            controller.resize(controller.host.bounds.size)
            model.tool = .marker; model.editWriting { $0.markerMode = .freehand; $0.markerWidth = 2 }
            let assistant = try XCTUnwrap(controller.host.drawingAssistant)
            assistant.begin(at: CGPoint(x: 80, y: 120)); assistant.move(samples: [CGPoint(x: 180, y: 120)]); assistant.end(cancelled: false)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, controller.host.canvas.drawing))
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performRedo()
            model.tool = .eraser; model.editWriting { $0.eraserTarget = .marker; $0.eraser = .partial }
            assistant.begin(at: CGPoint(x: 130, y: 120)); assistant.move(samples: [CGPoint(x: 130, y: 122)]); assistant.end(cancelled: false)
            XCTAssertNotNil(model.canvas.drawing.strokes.first?.mask)
            await model.performUndo(); XCTAssertNil(model.canvas.drawing.strokes.first?.mask)
            controller.finishAndClose(); parent.layoutIfNeeded()
            XCTAssertEqual(parent.surface.bounds.size, pageSize)
        }
    }
}
