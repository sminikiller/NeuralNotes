import XCTest
import UIKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class DiagramCompatibilityTests: XCTestCase {
    @MainActor private func fixture(_ run: (EditorViewModel, NativeDocumentStore) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await run(model, store); _ = await model.close() } catch { _ = await model.close(); throw error }
    }
    @MainActor private func backupCopy(_ model: EditorViewModel, store: NativeDocumentStore) async throws -> DocumentWorkspace {
        let saved = await model.flush(); XCTAssertTrue(saved)
        let manifest = try await model.workspace.manifest()
        let notebook = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Compatibilità diagrammi",
            createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let backup = try await model.workspace.exportNative(metadata: notebook)
        defer { try? FileManager.default.removeItem(at: backup) }
        let documentID = UUID(), notebookID = UUID()
        _ = try NativeImport.copy(from: backup, into: store, documentID: documentID, notebookID: notebookID)
        return DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
    }
    @MainActor func testWordHighlightColorAndLegacyMarksSurviveNativeBackupAndPDFExport() async throws {
        try await fixture { model, store in
            let legacy = PDFMarkup(kind: .underline, x: 60, y: 80, width: 100, height: 15, text: "Vecchio")
            let words = [PageWord(text: "Energia", rect: CGRect(x: 60, y: 100, width: 100, height: 20))]
            let marks = try WordHighlights.appending(words: words, indices: [0], to: [legacy], color: .green, width: 600, height: 800)
            model.page?.pdfMarkups = marks; model.drawingChanged(preservingRecognizedWords: true)
            let copy = try await backupCopy(model, store: store)
            let pages = try await copy.pages(), restored = try XCTUnwrap(pages.first)
            XCTAssertEqual(restored.pdfMarkups, marks); try PageValidation.validate(restored)
            let pdf = try await DocumentServices.exportPDF(workspace: copy)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
            let original = DocumentServices.image(page: try XCTUnwrap(model.page), drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 768).pngData()
            let imported = DocumentServices.image(page: restored, drawing: model.canvas.drawing, workspace: copy, maxDimension: 768).pngData()
            XCTAssertNotNil(original); XCTAssertEqual(imported, original)
        }
    }
    @MainActor func test026FixtureOpensSavesReopensExportsPDFAndImportsBackupWithSnapPreferences() async throws {
        try await fixture { model, store in
            let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/0.26.0")
            var legacy = try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: base.appendingPathComponent("page.json")))
            let profiles = try JSONDecoder().decode(NotebookWorkspaces.self, from: Data(contentsOf: base.appendingPathComponent("workspaces.json")))
            XCTAssertTrue(profiles.isValid); XCTAssertNil(legacy.connectors)
            let image = try await model.workspace.url("images/legacy.png")
            try Data(contentsOf: base.appendingPathComponent("legacy.png")).write(to: image)
            legacy.id = try XCTUnwrap(model.page?.id); legacy.revision = model.page?.revision ?? 0
            model.page = legacy; model.workspaces = profiles; model.workspaceSettingsDirty = true; model.drawingChanged()
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertEqual(model.page?.shapes, legacy.shapes); XCTAssertEqual(model.page?.texts, legacy.texts)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
            let copy = try await backupCopy(model, store: store)
            let pages = try await copy.pages(), catalog = try await copy.catalog()
            let restored = try XCTUnwrap(pages.first)
            XCTAssertNil(restored.connectors); XCTAssertEqual(restored.images.first?.perspective, legacy.images.first?.perspective)
            XCTAssertEqual(catalog.editorWorkspaces, profiles)
            for (actual, old) in zip(restored.shapes ?? [], legacy.shapes ?? []) {
                var expected = old; expected.id = actual.id; XCTAssertEqual(actual, expected)
            }
        }
    }
    @MainActor func testEditableAIMapBackupRemapsEndsLocalSourcesAndAudioSessions() async throws {
        try await fixture { model, store in
            let pageID = try XCTUnwrap(model.page?.id), documentID = model.workspace.documentID
            let artifact = AIArtifact(text: "Energia\nCalore [1]\nLavoro [1]", references: [.init(documentID: documentID, pageID: pageID)], provider: "Fixture", task: .outline)
            var map = try XCTUnwrap(MindMapLayout.page(from: artifact)); map.id = pageID; map.revision = model.page?.revision ?? 0
            let session = AudioSession(title: "Lezione collegata")
            try await model.workspace.saveSession(session)
            let anchor = StrokeAnchor(signature: "diagram", audioSessionID: session.id, seconds: 12)
            map.shapes?[0].audioAnchor = anchor; map.connectors?[0].audioAnchor = anchor
            var label = TextElement(text: "Flusso di energia"); label.rtf = RichText.data(NSAttributedString(string: label.text, attributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.blue]))
            map.connectors?[0].label = label.text; map.connectors?[0].labelRTF = label.rtf
            model.page = map; model.drawingChanged()
            let copy = try await backupCopy(model, store: store)
            let pages = try await copy.pages(), catalog = try await copy.catalog()
            let restored = try XCTUnwrap(pages.first), restoredSession = try XCTUnwrap(catalog.sessions.first)
            XCTAssertNotEqual(restored.id, pageID); XCTAssertNotEqual(restoredSession.id, session.id)
            XCTAssertEqual(restored.shapes?.count, 3); XCTAssertEqual(restored.connectors?.count, 2)
            XCTAssertTrue(restored.texts.isEmpty)
            XCTAssertTrue(Set(restored.objectIDs).isDisjoint(with: Set(map.objectIDs)))
            for edge in restored.connectors ?? [] {
                XCTAssertTrue(restored.connectorTargetIDs.contains(try XCTUnwrap(edge.from.objectID)))
                XCTAssertTrue(restored.connectorTargetIDs.contains(try XCTUnwrap(edge.to.objectID)))
            }
            let source = try XCTUnwrap(restored.shapes?[1].pageLink)
            XCTAssertEqual(source.documentID, copy.documentID); XCTAssertEqual(source.pageID, restored.id)
            XCTAssertEqual(restored.shapes?[0].audioAnchor?.audioSessionID, restoredSession.id)
            XCTAssertEqual(restored.connectors?[0].audioAnchor?.audioSessionID, restoredSession.id)
            XCTAssertEqual(restored.connectors?[0].audioAnchor?.seconds, 12)
            XCTAssertEqual(restored.connectors?[0].labelRTF, label.rtf)
            try PageValidation.validate(restored)
            let pdf = try await DocumentServices.exportPDF(workspace: copy)
            defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
        }
    }
    @MainActor func test027FixtureKeepsItsAppearanceAndLegacyMarkerSettingsThroughSavePDFAndNativeImport() async throws {
        try await fixture { model, store in
            let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/0.27.0")
            var old = try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: base.appendingPathComponent("page.json")))
            let profiles = try JSONDecoder().decode(NotebookWorkspaces.self, from: Data(contentsOf: base.appendingPathComponent("workspaces.json")))
            try PageValidation.validate(old); XCTAssertTrue(profiles.isValid)
            XCTAssertEqual(profiles.profiles.first?.writing?.effectiveEraserTarget, .marker)
            XCTAssertNil(profiles.profiles.first?.writing?.eraserTarget)
            let image = try await model.workspace.url("images/legacy.png")
            try Data(contentsOf: base.appendingPathComponent("legacy.png")).write(to: image)
            old.id = try XCTUnwrap(model.page?.id); old.revision = model.page?.revision ?? 0
            model.page = old; model.workspaces = profiles; model.workspaceSettingsDirty = true; model.drawingChanged()
            let original = DocumentServices.image(page: old, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 768).pngData()
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertEqual(model.page?.texts, old.texts); XCTAssertEqual(model.page?.shapes, old.shapes)
            XCTAssertEqual(model.page?.connectors, old.connectors); XCTAssertEqual(model.page?.images, old.images)
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: pdf) }
            let exported = try XCTUnwrap(PDFDocument(url: pdf))
            XCTAssertEqual(exported.pageCount, 1); XCTAssertTrue(exported.page(at: 0)?.string?.contains("0.27.0") == true)
            let copy = try await backupCopy(model, store: store)
            let pages = try await copy.pages(), restored = try XCTUnwrap(pages.first)
            try PageValidation.validate(restored)
            XCTAssertEqual(restored.connectors?.first?.label, "si conserva")
            XCTAssertEqual(restored.shapes?.first?.label, "Energia")
            let appearance = DocumentServices.image(page: restored, drawing: model.canvas.drawing, workspace: copy, maxDimension: 768).pngData()
            XCTAssertNotNil(original); XCTAssertEqual(appearance, original, "Gli ID nuovi del backup non cambiano la pagina visibile")
            let catalog = try await copy.catalog(); XCTAssertEqual(catalog.editorWorkspaces, profiles)
        }
    }
}
