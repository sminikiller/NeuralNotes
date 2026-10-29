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
            let shape = ShapeElement(kind: .rectangle, x: 60, y: 100, width: 100, height: 100)
            model.mutatePage("Fixture") { $0.shapes = [shape] }
            model.selectedIDs = [shape.id]; model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            model.arrangeSelection(.top)
            XCTAssertEqual(model.selectedInkBounds.minY, 100, accuracy: 0.1)
            await model.performUndo(); XCTAssertEqual(EditorInkSignatures.make(model.canvas.drawing), signatures)
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
}
