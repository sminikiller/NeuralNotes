import XCTest
@testable import NeuralNotesCore

final class ShapeLegacyCompatibilityTests: XCTestCase {
    private func legacy() throws -> PageSnapshot {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/0.24.1/page.json")
        return try JSONDecoder().decode(PageSnapshot.self, from: Data(contentsOf: file))
    }
    func testLegacyShapeFieldsRemainAbsentAndGeometryUnchangedThroughJSON() throws {
        let original = try legacy()
        XCTAssertNoThrow(try PageValidation.validate(original)); XCTAssertEqual(original.shapes?.count, 3)
        for shape in original.shapes ?? [] {
            XCTAssertNil(shape.fill); XCTAssertNil(shape.dash); XCTAssertNil(shape.cornerRadius)
            XCTAssertNil(shape.audioAnchor); XCTAssertFalse(ShapeGeometry.path(for: shape).commands.isEmpty)
        }
        let restored = try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }
    func testLegacyPageSaveAndNativeBackupKeepAllOldContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let added = try await workspace.addPage()
        var page = try legacy(); page.id = added.id; page.revision = added.revision + 1
        let fixtureImage = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/0.24.1/legacy.png")
        let imageURL = try await workspace.url("images/legacy.png")
        try Data(contentsOf: fixtureImage).write(to: imageURL)
        let saved = try await workspace.save(page, drawing: Data([1, 2, 3, 4]))
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Compatibilità 0.24.1", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        let archive = try await workspace.exportNative(metadata: metadata)
        defer { try? FileManager.default.removeItem(at: archive) }
        let documentID = UUID(), notebookID = UUID()
        _ = try NativeImport.copy(from: archive, into: store, documentID: documentID, notebookID: notebookID)
        let copy = DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
        let pages = try await copy.pages(), restored = try XCTUnwrap(pages.first)
        XCTAssertEqual(restored.shapes?.count, saved.shapes?.count)
        XCTAssertEqual(restored.texts.count, saved.texts.count); XCTAssertEqual(restored.images.count, saved.images.count)
        for (actual, source) in zip(restored.shapes ?? [], saved.shapes ?? []) {
            XCTAssertNotEqual(actual.id, source.id)
            var expected = source; expected.id = actual.id; XCTAssertEqual(actual, expected)
        }
        for (actual, source) in zip(restored.texts, saved.texts) {
            XCTAssertNotEqual(actual.id, source.id)
            var expected = source; expected.id = actual.id; XCTAssertEqual(actual, expected)
        }
        for (actual, source) in zip(restored.images, saved.images) {
            XCTAssertNotEqual(actual.id, source.id)
            var expected = source; expected.id = actual.id; XCTAssertEqual(actual, expected)
        }
        let restoredImage = try await copy.url("images/legacy.png")
        XCTAssertEqual(try Data(contentsOf: restoredImage), try Data(contentsOf: imageURL))
        let bytes = try await copy.drawing(restored); XCTAssertEqual(bytes, Data([1, 2, 3, 4]))
    }
}
