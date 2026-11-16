import XCTest
import UIKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class StudyKitIntegrationTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        try await run(model)
        let closed = await model.close(); XCTAssertTrue(closed)
    }
    @MainActor func testStudyObjectsUndoPersistAndExportAnswersWithoutChangingTape() async throws {
        try await fixture { model in
            model.insertStudyNote(text: "Risposta segreta", kind: .review, color: .mint)
            let note = try XCTUnwrap(model.page?.texts.first)
            model.toggleStudyNote(note.id); XCTAssertEqual(model.page?.texts.first?.studyNote?.collapsed, true)
            await model.performUndo(); XCTAssertEqual(model.page?.texts.first?.studyNote?.collapsed, false)
            model.addStudyTape(color: .pink, style: .striped, width: 140, height: 32)
            let tape = try XCTUnwrap(model.page?.tapes?.first)
            await model.performUndo(); XCTAssertTrue(model.page?.tapes?.isEmpty ?? true)
            await model.performRedo(); XCTAssertEqual(model.page?.tapes?.first, tape)
            model.beginStudyReview(); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            model.revealNextStudyTape(); XCTAssertEqual(model.page?.tapes?.first?.revealed, true)
            model.endStudyReview(); XCTAssertFalse(model.studyReview)
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let id = try XCTUnwrap(model.page?.id)
            let saved = try await model.workspace.pageSnapshot(id)
            XCTAssertEqual(saved.texts.first?.studyNote, note.studyNote)
            XCTAssertEqual(saved.tapes?.first?.color, .pink)
            let url = try await DocumentServices.exportPDF(workspace: model.workspace, pageIDs: [id], studyTapes: .answers)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertNotNil(PDFDocument(url: url))
            let afterExport = try await model.workspace.pageSnapshot(id)
            XCTAssertEqual(afterExport, saved)
        }
    }
    @MainActor func testMapConnectionsFollowMoveAndListKeepsRichTextOnReopen() async throws {
        try await fixture { model in
            model.insertStudyDiagram(.mindMap, color: .blue, oval: false)
            let initial = try XCTUnwrap(model.page), first = try XCTUnwrap(initial.shapes?.first), edge = try XCTUnwrap(initial.connectors?.first)
            let before = ConnectorGeometry.resolve(edge.from, objects: DiagramObjects.make(initial))
            model.mutatePage("Sposta nodo") { $0.shapes?[0].x += 30 }
            let moved = try XCTUnwrap(model.page)
            let after = ConnectorGeometry.resolve(edge.from, objects: DiagramObjects.make(moved))
            XCTAssertEqual(after.x - before.x, 30, accuracy: 0.01)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.first, first)
            await model.performUndo(); XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            await model.performRedo(); XCTAssertEqual(model.page?.connectors, initial.connectors)
            let target = PageLinkTarget(documentID: model.workspace.documentID, pageID: UUID())
            model.mutatePage("Collega nodo") { $0.shapes?[0].pageLink = target }
            model.removePageLink(from: first.id)
            XCTAssertNil(model.page?.shapes?.first?.pageLink)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.first?.pageLink, target)
            await model.performRedo(); XCTAssertNil(model.page?.shapes?.first?.pageLink)
            model.insertStudyList("Organi\n  Cuore\nTessuti", title: "Anatomia", kind: 2, color: .yellow)
            let list = try XCTUnwrap(model.page?.texts.last)
            XCTAssertTrue(list.text.contains("☐ Cuore")); XCTAssertNotNil(list.rtf)
            let attributed = RichText.attributed(list)
            XCTAssertEqual(attributed.string, list.text)
            let flushed = await model.flush(); XCTAssertTrue(flushed)
            let saved = try await model.workspace.pageSnapshot(try XCTUnwrap(model.page?.id))
            XCTAssertEqual(saved.texts.last, list); try PageValidation.validate(saved)
        }
    }
}
