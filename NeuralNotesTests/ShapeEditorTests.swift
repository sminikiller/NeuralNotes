import XCTest
import UIKit
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class ShapeEditorTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await run(model); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor func testNewShapesStyleHandlesUndoAndPDFUseTheSameGeometry() async throws {
        try await fixture { model in
            for kind in ShapeKind.allCases {
                model.addDraggedShape(kind, from: .init(x: 100, y: 200), to: .init(x: 320, y: 380))
                XCTAssertEqual(model.page?.shapes?.last?.kind, kind)
            }
            model.selectedIDs = Set(model.page?.shapes?.map(\.id) ?? [])
            let original = model.page?.shapes
            var style = ShapeStyle(); style.fill = .yellow; style.fillOpacity = 0.3
            style.dash = .dashed; style.cornerRadius = 12; style.arrowHeads = .both; style.arrowStyle = .filled
            model.applyShapeStyle(style)
            XCTAssertTrue(model.page?.shapes?.allSatisfy { $0.fill == .yellow && $0.dash == .dashed } == true)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes, original)
            await model.performRedo()
            let saved = await model.flush(); XCTAssertTrue(saved)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
            let image = DocumentServices.image(page: try XCTUnwrap(model.page), drawing: model.canvas.drawing, workspace: model.workspace)
            XCTAssertNotNil(image.cgImage)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertTrue(model.page?.shapes?.allSatisfy { $0.fill == .yellow && $0.dash == .dashed } == true)
        }
    }
    @MainActor func testEditableRecognitionUndoRestoresOriginalInkAndAnchors() async throws {
        try await fixture { model in
            model.editShapePreferences { $0.mode = .automatic; $0.output = .editable }
            let points = (0...40).map { index in StrokeSample(x: 90 + Double(index) * 5, y: 170 + sin(Double(index))) }
            let controls = points.enumerated().map { index, p in PKStrokePoint(location: CGPoint(x: p.x, y: p.y), timeOffset: Double(index) * 0.02,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 0.6, azimuth: 0, altitude: .pi / 2) }
            let original = PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [original])
            let signature = try XCTUnwrap(EditorInkSignatures.make(model.canvas.drawing).first)
            let anchor = StrokeAnchor(signature: signature, audioSessionID: UUID(), seconds: 42)
            model.page?.anchors = [anchor]
            model.pendingHeldShape = (try XCTUnwrap(model.page?.id), .line, points)
            model.pendingShapeRecognition = ShapeRecognizer.recognize(points, mode: .automatic)
            model.pendingAutomaticRecognition = true
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertEqual(model.page?.shapes?.first?.audioAnchor, anchor)
            XCTAssertEqual(model.page?.shapes?.first?.kind, .line)
            XCTAssertNotNil(model.recognitionNotice)
            await model.performUndo()
            XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), [signature]); XCTAssertEqual(model.page?.anchors, [anchor])
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performRedo(); await model.performRedo()
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertEqual(model.page?.shapes?.first?.audioAnchor, anchor)
        }
    }
    @MainActor func testOldPageFixtureOpensSavesAndExportsPDFAndNativeBackup() async throws {
        try await fixture { model in
            let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tests/Fixtures/0.24.1/page.json")
            var legacy = try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: file))
            let imageFile = try await model.workspace.url("images/legacy.png")
            try Data(contentsOf: file.deletingLastPathComponent().appendingPathComponent("legacy.png")).write(to: imageFile)
            legacy.id = try XCTUnwrap(model.page?.id); legacy.revision = model.page?.revision ?? 0
            model.page = legacy; model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page)); XCTAssertEqual(model.page?.shapes, legacy.shapes)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
            let manifest = try JSONDecoder().decode(DocumentManifest.self, from: Data(contentsOf: model.workspace.package.appendingPathComponent("manifest.json")))
            let notebook = Notebook(id: manifest.notebookID, documentID: model.workspace.documentID,
                title: "Legacy", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
            let backup = try await model.workspace.exportNative(metadata: notebook)
            defer { try? FileManager.default.removeItem(at: backup) }
            XCTAssertGreaterThan(try Data(contentsOf: backup).count, 100)
        }
    }
    @MainActor func testRecognitionShapeReplayDoesNotWriteIntoTheNotebook() async throws {
        try await fixture { model in
            let session = AudioSession(title: "Fixture")
            model.audio = AudioController(workspace: model.workspace); model.audio?.sessions = [session]
            model.addDraggedShape(.rectangle, from: .init(x: 40, y: 50), to: .init(x: 220, y: 170))
            var page = try XCTUnwrap(model.page)
            page.shapes?[0].audioAnchor = StrokeAnchor(signature: "shape", audioSessionID: session.id, seconds: 10)
            model.page = page
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = page
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800); host.layoutIfNeeded()
            model.audio?.replayInk = true; model.audio?.playingSessionID = session.id; model.audio?.playback = 0
            host.inkReplay.update(host)
            XCTAssertEqual(host.surface.replayHiddenObjectIDs.count, 1); XCTAssertEqual(model.page, page)
            model.audio?.playback = 15; host.inkReplay.update(host)
            XCTAssertTrue(host.surface.replayHiddenObjectIDs.isEmpty); XCTAssertEqual(model.page, page)
            model.audio?.playingSessionID = nil; host.inkReplay.update(host)
        }
    }
}
