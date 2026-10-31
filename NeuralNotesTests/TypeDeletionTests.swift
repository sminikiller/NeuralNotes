import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class TypeDeletionTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, Notebook) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Eliminazioni", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        await model.open()
        do { try await body(model, metadata); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func stroke(marker: Bool, date: Date) -> PKStroke {
        let points = [CGPoint(x: 40, y: 70), CGPoint(x: 220, y: 70)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: marker ? 15 : 3, height: marker ? 15 : 3), opacity: marker ? 0.4 : 1, force: 0.8, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(marker ? .marker : .pen, color: marker ? .yellow : .black), path: PKStrokePath(controlPoints: points, creationDate: date))
    }
    @MainActor func testSinglePageCountsRespectLocksAndOneUndoRestoresImagesAfterCleanup() async throws {
        try await fixture { model, _ in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { item in UIColor.green.setFill(); item.fill(CGRect(x: 0, y: 0, width: 16, height: 16)) }
            let bytes = try XCTUnwrap(image.pngData()), file = try await model.workspace.storeImage(bytes)
            let normal = TextElement(text: "Eliminare"), locked = TextElement(text: "Protetto")
            var note = TextElement(text: "Risposta della Lente")
            note.lensNote = LensNoteInfo(title: "Lente", source: .init(pageID: try XCTUnwrap(model.page?.id), rect: .init(x: 10, y: 10, width: 40, height: 20)))
            let picture = ImageElement(file: file, width: 80, height: 80)
            model.page?.texts = [normal, locked, note]; model.page?.lockedObjects = [locked.id]; model.page?.images = [picture]
            model.drawingChanged(); model.history.clear()
            let id = try XCTUnwrap(model.page?.id), preview = try await model.typeDeletionPreview(pageIDs: [id])
            XCTAssertFalse(preview.requiresBackup); XCTAssertEqual(preview.counts[.text], 1); XCTAssertEqual(preview.counts[.lensNotes], 1)
            let removed = try await model.deleteTypes([.text, .images], preview: preview)
            XCTAssertEqual(removed, 2); XCTAssertEqual(model.page?.texts, [locked, note]); XCTAssertTrue(model.page?.images.isEmpty == true)
            _ = try await model.workspace.cleanUnusedFiles()
            let url = try await model.workspace.url(file); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            await model.performUndo(); XCTAssertEqual(model.page?.texts, [normal, locked, note]); XCTAssertEqual(model.page?.images, [picture])
            XCTAssertEqual(try Data(contentsOf: url), bytes); XCTAssertFalse(model.canUndo)
            await model.performRedo(); XCTAssertEqual(model.page?.texts, [locked, note]); XCTAssertTrue(model.page?.images.isEmpty == true)
        }
    }
    @MainActor func testDeletingMarkerRebasesRepeatedStrokeAudioSignaturesAndRetainsPenExactly() async throws {
        try await fixture { model, _ in
            var session = AudioSession(title: "Registrazione conservata"); session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
            try await model.workspace.saveSession(session)
            let date = Date(), pen = stroke(marker: false, date: date), marker = stroke(marker: true, date: date)
            let drawing = PKDrawing(strokes: [marker, pen]), keys = EditorInkSignatures.make(drawing)
            model.canvas.drawing = drawing
            model.page?.anchors = [StrokeAnchor(signature: keys[0], audioSessionID: session.id, seconds: 1), StrokeAnchor(signature: keys[1], audioSessionID: session.id, seconds: 2)]
            model.page?.pdfMarkups = [.init(kind: .highlight, x: 20, y: 50, width: 80, height: 14, text: "Colore"), .init(kind: .underline, x: 20, y: 100, width: 80, height: 14, text: "Penna")]
            model.drawingChanged(); model.history.clear()
            let preview = try await model.typeDeletionPreview(pageIDs: [try XCTUnwrap(model.page?.id)])
            XCTAssertEqual(preview.counts[.marker], 2); XCTAssertEqual(preview.counts[.pen], 2)
            let removed = try await model.deleteTypes([.marker], preview: preview)
            XCTAssertEqual(removed, 2); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: [pen])))
            XCTAssertEqual(model.page?.anchors.first?.seconds, 2); XCTAssertEqual(model.page?.anchors.first?.signature, EditorInkSignatures.make(model.canvas.drawing).first)
            XCTAssertEqual(model.page?.pdfMarkups?.count, 1); XCTAssertEqual(model.page?.pdfMarkups?.first?.kind, .underline)
            let catalog = try await model.workspace.catalog(); XCTAssertEqual(catalog.sessions, [session])
            await model.performUndo(); XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing)); XCTAssertEqual(model.page?.anchors.count, 2)
        }
    }
    @MainActor func testWholeNotebookRequiresBackupAndFailureLeavesEveryPageUnchanged() async throws {
        try await fixture { model, _ in
            model.addStickyNote("Prima"); await model.addPage(); model.addStickyNote("Seconda")
            let preview = try await model.typeDeletionPreview(pageIDs: Set(model.pages.map(\.id)))
            XCTAssertTrue(preview.requiresBackup)
            let before = try await model.workspace.pages(); model.history.clear()
            do { _ = try await model.deleteTypes([.text], preview: preview); XCTFail("Il backup è obbligatorio.") }
            catch TypeDeletionFailure.backupRequired { }
            let after = try await model.workspace.pages(); XCTAssertEqual(after, before); XCTAssertFalse(model.canUndo)
            let backups = try await model.workspace.automaticBackups(); XCTAssertTrue(backups.isEmpty)
        }
    }
    @MainActor func testCountsAndDeletes120PagesWithForcedBackupAndOneLogicalUndo() async throws {
        try await fixture { model, metadata in
            model.backupMetadata = metadata
            model.addStickyNote("Pagina 1"); let saved = await model.flush(); XCTAssertTrue(saved)
            let inputs = (2...120).map { number -> PageSnapshot in var page = PageSnapshot(); page.texts = [TextElement(text: "Pagina \(number)")]; return page }
            _ = try await model.workspace.appendPages(inputs); model.pages = try await model.workspace.pages()
            let before = try await model.workspace.pages(); model.history.clear()
            var completed = 0
            let preview = try await model.typeDeletionPreview(pageIDs: Set(model.pages.map(\.id)), wholeNotebook: true) { done, _ in completed = done }
            XCTAssertEqual(completed, 120); XCTAssertEqual(preview.counts[.text], 120)
            let removed = try await model.deleteTypes([.text], preview: preview)
            XCTAssertEqual(removed, 120)
            let backups = try await model.workspace.automaticBackups(); XCTAssertEqual(backups.count, 1)
            let empty = try await model.workspace.pages(); XCTAssertTrue(empty.allSatisfy { $0.texts.isEmpty })
            await model.performUndo()
            let restored = try await model.workspace.pages(); XCTAssertEqual(restored.map(\.texts), before.map(\.texts)); XCTAssertFalse(model.canUndo)
            await model.performRedo(); let again = try await model.workspace.pages(); XCTAssertTrue(again.allSatisfy { $0.texts.isEmpty })
        }
    }
    @MainActor func testRecordingAndStalePreviewRefuseMutation() async throws {
        try await fixture { model, metadata in
            model.backupMetadata = metadata; model.addStickyNote("Conservare")
            let preview = try await model.typeDeletionPreview(pageIDs: [try XCTUnwrap(model.page?.id)])
            let original = try XCTUnwrap(model.page)
            var session = AudioSession(title: "In corso"); session.state = "recording"; session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
            try await model.workspace.saveSession(session)
            do { _ = try await model.deleteTypes([.text], preview: preview); XCTFail("Registrazione attiva.") }
            catch TypeDeletionFailure.unavailable { }
            session.state = "paused"; session.revision = 1; try await model.workspace.saveSession(session)
            var newer = original; newer.revision += 1; newer.texts.append(TextElement(text: "Modifica esterna"))
            let saved = try await model.workspace.save(newer, drawing: model.canvas.drawing.dataRepresentation())
            do { _ = try await model.deleteTypes([.text], preview: preview); XCTFail("Conteggio obsoleto.") }
            catch TypeDeletionFailure.changed { }
            let unchanged = try await model.workspace.pageSnapshot(original.id); XCTAssertEqual(unchanged, saved)
        }
    }
    @MainActor func testAudioLinksDeletionKeepsSessionsAndEveryNativeStroke() async throws {
        try await fixture { model, _ in
            var session = AudioSession(title: "Lezione"); session.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
            try await model.workspace.saveSession(session)
            let drawing = PKDrawing(strokes: [stroke(marker: false, date: Date())]); model.canvas.drawing = drawing
            let anchor = StrokeAnchor(signature: try XCTUnwrap(EditorInkSignatures.make(drawing).first), audioSessionID: session.id, seconds: 0)
            model.page?.anchors = [anchor]
            var shape = ShapeElement(kind: .ellipse); shape.audioAnchor = anchor
            model.page?.shapes = [shape]; model.drawingChanged(); model.history.clear()
            let preview = try await model.typeDeletionPreview(pageIDs: [try XCTUnwrap(model.page?.id)])
            XCTAssertEqual(preview.counts[.audioLinks], 2)
            let removed = try await model.deleteTypes([.audioLinks], preview: preview)
            XCTAssertEqual(removed, 2); XCTAssertTrue(model.page?.anchors.isEmpty == true); XCTAssertNil(model.page?.shapes?.first?.audioAnchor)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, drawing))
            let catalog = try await model.workspace.catalog(); XCTAssertEqual(catalog.sessions, [session])
            await model.performUndo(); XCTAssertEqual(model.page?.anchors, [anchor]); XCTAssertEqual(model.page?.shapes?.first?.audioAnchor, anchor)
        }
    }
}
