import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class SelectiveEraseTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func stroke(_ points: [CGPoint], marker: Bool = false) -> PKStroke {
        let samples = points.enumerated().map { i, p in PKStrokePoint(location: p, timeOffset: Double(i) * 0.01,
            size: CGSize(width: marker ? 16 : 3, height: marker ? 16 : 3), opacity: marker ? 0.4 : 1, force: 0.8, azimuth: 0, altitude: .pi / 2) }
        return PKStroke(ink: PKInk(marker ? .marker : .pen, color: marker ? .yellow : .black), path: PKStrokePath(controlPoints: samples, creationDate: Date()), randomSeed: 37)
    }
    @MainActor private func imageFile(_ model: EditorViewModel) async throws -> String {
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { item in UIColor.red.setFill(); item.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        return try await model.workspace.storeImage(try XCTUnwrap(picture.pngData()))
    }
    @MainActor func testEveryTargetOnlyErasesItsTypeAndOneUndoRestoresAllNativeState() async throws {
        for target in EraserTarget.allCases {
            try await fixture { model in
                let drawing = PKDrawing(strokes: [stroke([.init(x: 50, y: 80), .init(x: 250, y: 80)]), stroke([.init(x: 50, y: 80), .init(x: 250, y: 80)], marker: true)])
                var page = try XCTUnwrap(model.page)
                var text = TextElement(text: "Elemento"); text.x = 100; text.y = 30; text.width = 100
                page.texts = [text]
                var picture = ImageElement(file: try await imageFile(model), width: 100, height: 40); picture.x = 100; picture.y = 100
                page.images = [picture]
                let shape = ShapeElement(kind: .rectangle, x: 100, y: 160, width: 100, height: 60)
                let locked = ShapeElement(kind: .ellipse, x: 100, y: 220, width: 100, height: 40)
                page.shapes = [shape, locked]; page.lockedObjects = [locked.id]
                page.connectors = [ConnectorElement(from: .init(x: 50, y: 150), to: .init(x: 250, y: 150), routing: .straight)]
                page.tapes = [StudyTape(x: 100, y: 270, width: 100, height: 30)]
                page.pdfMarkups = [.init(kind: .highlight, x: 100, y: 310, width: 100, height: 10, text: "PDF")]
                model.page = page; model.installNativeInk(drawing); model.history.clear()
                model.chooseTool(.eraser); model.editWriting { $0.eraserTarget = target; $0.eraser = .stroke; $0.eraserWidth = 8 }
                XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
                let session = SelectiveEraseSession(model: model)
                session.append([.init(x: 150, y: 10), .init(x: 150, y: 340)]); session.finish(cancelled: false)
                XCTAssertEqual(model.canvas.drawing.strokes.count, target == .all ? 0 : target == .marker || target == .pen ? 1 : 2, target.title)
                XCTAssertEqual(model.page?.texts.count, target == .all || target == .text ? 0 : 1, target.title)
                XCTAssertEqual(model.page?.images.count, target == .all || target == .images ? 0 : 1, target.title)
                XCTAssertEqual(model.page?.shapes?.count, target == .all || target == .shapes ? 1 : 2, target.title)
                XCTAssertEqual(model.page?.connectors?.count, target == .all || target == .shapes ? 0 : 1, target.title)
                XCTAssertEqual(model.page?.tapes?.count, target == .all ? 0 : 1, target.title)
                XCTAssertEqual(model.page?.pdfMarkups?.count, target == .all || target == .marker ? 0 : 1, target.title)
                XCTAssertTrue(model.canUndo); await model.performUndo(); XCTAssertFalse(model.canUndo)
                XCTAssertEqual(model.page?.texts, page.texts); XCTAssertEqual(model.page?.images, page.images)
                XCTAssertEqual(model.page?.shapes, page.shapes); XCTAssertEqual(model.page?.connectors, page.connectors)
                XCTAssertEqual(model.page?.tapes, page.tapes); XCTAssertEqual(model.page?.pdfMarkups, page.pdfMarkups)
                XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing))
                await model.performRedo(); XCTAssertTrue(model.canUndo); XCTAssertFalse(model.hasActiveStroke)
            }
        }
    }
    @MainActor func testObjectTogglePreservesObjectsWhileErasingInkThenErasesObjectsWithOneUndo() async throws {
        try await fixture { model in
            let drawing = PKDrawing(strokes: [stroke([.init(x: 50, y: 80), .init(x: 250, y: 80)])])
            var image = ImageElement(file: try await imageFile(model), width: 100, height: 40); image.x = 100; image.y = 100
            let shape = ShapeElement(kind: .rectangle, x: 100, y: 160, width: 100, height: 60)
            let locked = ShapeElement(kind: .rectangle, x: 100, y: 240, width: 100, height: 40)
            model.page?.images = [image]; model.page?.shapes = [shape, locked]; model.page?.lockedObjects = [locked.id]
            model.installNativeInk(drawing); model.history.clear(); model.chooseTool(.eraser)
            model.editWriting { $0.eraserTarget = .all; $0.eraseObjects = false; $0.eraser = .stroke; $0.eraserWidth = 8 }
            XCTAssertFalse(model.writingOptions.erasesObjects)
            let inkOnly = SelectiveEraseSession(model: model)
            inkOnly.append([.init(x: 150, y: 30), .init(x: 150, y: 300)]); inkOnly.finish(cancelled: false)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertEqual(model.page?.images, [image]); XCTAssertEqual(model.page?.shapes, [shape, locked])
            await model.performUndo(); XCTAssertFalse(model.canUndo); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing))
            model.editWriting { $0.eraseObjects = true }
            let all = SelectiveEraseSession(model: model)
            all.append([.init(x: 150, y: 30), .init(x: 150, y: 300)]); all.finish(cancelled: false)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertTrue(model.page?.images.isEmpty == true)
            XCTAssertEqual(model.page?.shapes, [locked])
            await model.performUndo(); XCTAssertFalse(model.canUndo)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing)); XCTAssertEqual(model.page?.images, [image]); XCTAssertEqual(model.page?.shapes, [shape, locked])
            let word = PageWord(text: "Energia", rect: CGRect(x: 100, y: 320, width: 100, height: 20))
            model.page?.pdfMarkups = try WordHighlights.appending(words: [word], indices: [0], to: [], color: .yellow, width: 600, height: 800)
            let marks = model.page?.pdfMarkups; model.history.clear()
            model.editWriting { $0.eraserTarget = .marker; $0.eraseObjects = false }
            let marker = SelectiveEraseSession(model: model); marker.append([.init(x: 150, y: 330)]); marker.finish(cancelled: false)
            XCTAssertTrue(model.page?.pdfMarkups?.isEmpty == true); XCTAssertEqual(model.page?.images, [image])
            await model.performUndo(); XCTAssertEqual(model.page?.pdfMarkups, marks)
        }
    }
    @MainActor func testEmptyInteriorOfInkAndUnfilledEllipseIsNotAnEraserHit() async throws {
        try await fixture { model in
            let points = (0...100).map { i -> CGPoint in let a = Double(i) * .pi * 2 / 100; return CGPoint(x: 200 + cos(a) * 80, y: 200 + sin(a) * 80) }
            let drawing = PKDrawing(strokes: [stroke(points)])
            model.installNativeInk(drawing); model.page?.shapes = [ShapeElement(kind: .ellipse, x: 120, y: 120, width: 160, height: 160)]
            let original = model.page
            model.chooseTool(.eraser); model.editWriting { $0.eraserTarget = .all; $0.eraser = .stroke; $0.eraserWidth = 8 }
            let session = SelectiveEraseSession(model: model); session.append([.init(x: 200, y: 200)]); session.finish(cancelled: false)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing)); XCTAssertEqual(model.page, original); XCTAssertFalse(model.canUndo)
        }
    }
    @MainActor func testAnErasedGapDoesNotDeleteTheRemainingStrokeButVisibleContactDoes() async throws {
        try await fixture { model in
            let original = stroke([.init(x: 50, y: 200), .init(x: 350, y: 200)])
            model.installNativeInk(PKDrawing(strokes: [original])); model.chooseTool(.eraser)
            model.editWriting { $0.eraserTarget = .pen; $0.eraser = .partial; $0.eraserWidth = 30 }
            let first = SelectiveEraseSession(model: model); first.append([.init(x: 200, y: 200)]); first.finish(cancelled: false)
            let clipped = model.canvas.drawing
            XCTAssertNotNil(clipped.strokes.first?.mask); XCTAssertEqual(clipped.strokes.first?.randomSeed, original.randomSeed)
            model.history.clear(); model.editWriting { $0.eraser = .stroke; $0.eraserWidth = 4 }
            let gap = SelectiveEraseSession(model: model); gap.append([.init(x: 200, y: 200)]); gap.finish(cancelled: false)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, clipped)); XCTAssertFalse(model.canUndo)
            let hit = SelectiveEraseSession(model: model); hit.append([.init(x: 100, y: 200)]); hit.finish(cancelled: false)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo(); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, clipped)); XCTAssertFalse(model.canUndo)
        }
    }
    @MainActor func testRotatedImageOnlyErasesOnItsActualRectangleAndCancelRestoresIt() async throws {
        try await fixture { model in
            var image = ImageElement(file: try await imageFile(model), width: 200, height: 60)
            image.x = 100; image.y = 170; image.rotation = 45
            model.page?.images = [image]; let original = model.page
            model.chooseTool(.eraser); model.editWriting { $0.eraserTarget = .images; $0.eraserWidth = 4 }
            let outside = SelectiveEraseSession(model: model); outside.append([.init(x: 113, y: 285)]); outside.finish(cancelled: false)
            XCTAssertEqual(model.page?.images, [image]); XCTAssertFalse(model.canUndo)
            let touching = SelectiveEraseSession(model: model); touching.append([.init(x: 200, y: 200)])
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(model.page?.images.isEmpty == true); XCTAssertFalse(model.dirty)
            touching.finish(cancelled: true)
            XCTAssertEqual(model.page, original); XCTAssertFalse(model.canUndo); XCTAssertFalse(model.hasActiveStroke)
        }
    }
    @MainActor func testSpatialIndexAndVisibleOutlineCacheLimitWorkWith2000Strokes() async throws {
        try await fixture { model in
            let strokes = (0..<2000).map { index -> PKStroke in
                let x = CGFloat(index % 50) * 35, y = CGFloat(index / 50) * 35
                return stroke([CGPoint(x: x, y: y), CGPoint(x: x + 20, y: y)])
            }
            model.installNativeInk(PKDrawing(strokes: strokes)); model.chooseTool(.eraser)
            model.editWriting { $0.eraserTarget = .pen; $0.eraserWidth = 4; $0.eraser = .partial }
            let session = SelectiveEraseSession(model: model)
            for x in [10.0, 11, 12] { session.append([.init(x: x, y: 0)]); try await Task.sleep(for: .milliseconds(30)) }
            XCTAssertLessThanOrEqual(session.outlineBuilds, 2, "Non si devono ricostruire i contorni di duemila tratti a ogni campione.")
            session.finish(cancelled: false); XCTAssertTrue(model.canUndo)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 2000)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: strokes)))
        }
    }
    @MainActor func testHugeFiniteRotationsRemainFiniteInHitTestingRenderingAndSelection() async throws {
        try await fixture { model in
            var image = ImageElement(file: try await imageFile(model), width: 140, height: 60)
            image.x = 100; image.y = 200; image.rotation = .greatestFiniteMagnitude
            var text = TextElement(text: "Rotazione valida"); text.x = 100; text.width = 180; text.rotation = -.greatestFiniteMagnitude
            model.page?.images = [image]; model.page?.texts = [text]
            let page = try XCTUnwrap(model.page); try PageValidation.validate(page)
            let regions = EraserObjectGeometry.regions(page: page, target: .all)
            XCTAssertEqual(regions.count, 2)
            for path in regions.values {
                let box = path.boundingBoxOfPath
                XCTAssertTrue([box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite))
            }
            let transform = RichText.rotation(text, pageHeight: page.height)
            XCTAssertTrue([transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite))
            model.selectedIDs = [image.id, text.id]
            XCTAssertNoThrow(try model.selectionImage())
            let rendered = DocumentServices.image(page: page, drawing: PKDrawing(), workspace: model.workspace, maxDimension: 400)
            XCTAssertGreaterThan(rendered.size.width, 0)
        }
    }
    @MainActor func testTouchingAGapInADashedShapeDoesNotEraseItsVisibleDashes() async throws {
        try await fixture { model in
            var line = ShapeElement(kind: .line, x: 100, y: 100, width: 200, height: 1, lineWidth: 10)
            line.dash = .dashed; model.page?.shapes = [line]
            model.chooseTool(.eraser); model.editWriting { $0.eraserTarget = .shapes; $0.eraserWidth = 4 }
            let gap = SelectiveEraseSession(model: model); gap.append([.init(x: 140, y: 100.5)]); gap.finish(cancelled: false)
            XCTAssertEqual(model.page?.shapes, [line]); XCTAssertFalse(model.canUndo)
            let dash = SelectiveEraseSession(model: model); dash.append([.init(x: 110, y: 100.5)]); dash.finish(cancelled: false)
            XCTAssertTrue(model.page?.shapes?.isEmpty == true)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, [line])
        }
    }
}
