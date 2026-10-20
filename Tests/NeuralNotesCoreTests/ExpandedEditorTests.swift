import XCTest
@testable import NeuralNotesCore

final class ExpandedEditorTests: XCTestCase {
    func testHexColorsRoundTripAndRejectMalformedValues() {
        for value in ["#000000", "#FFFFFF", "#173A80", "#00FF2A"] { XCTAssertEqual(InkColor(hex: value)?.hex, value) }
        for value in ["#F00", "##FF0000", "FF00000", "zz0000", "#FF 000"] { XCTAssertNil(InkColor(hex: value)) }
        XCTAssertEqual(InkColor(.nan, 0, 0).hex, "#000000")
    }
    func testListsContinueNumbersIndentationAndResetCheckboxes() {
        XCTAssertEqual(TextLists.continuation(of: "3. Appunto")?.prefix, "4. ")
        XCTAssertEqual(TextLists.continuation(of: "  • Appunto")?.prefix, "  • ")
        XCTAssertEqual(TextLists.continuation(of: "☑ Completato")?.prefix, "☐ ")
        XCTAssertTrue(TextLists.continuation(of: "- ")?.empty == true)
        XCTAssertNil(TextLists.continuation(of: "Testo normale"))
    }
    func testAllPaperTemplatesRoundTripWithoutChangingOldFormats() throws {
        for style in PaperStyle.allCases {
            let template = PageTemplate(paper: style)
            let restored = try JSONDecoder().decode(PageTemplate.self, from: JSONEncoder().encode(template))
            XCTAssertEqual(restored.makePage().paper, style); XCTAssertEqual(restored.makePage().width, 768)
        }
        XCTAssertEqual(try JSONDecoder().decode(PaperStyle.self, from: Data("\"grid\"".utf8)), .grid)
    }
    func testFSRSCardMigrationPersistsMemoryAndKeepsSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let now = Date(timeIntervalSince1970: 1_700_000_000), reference = SourceReference(documentID: manifest.documentID)
        let card = StudyCard(question: "Domanda", answer: "Risposta", source: reference, now: now)
        try await workspace.addStudyCards([card]); try await workspace.setAdaptiveReview(true)
        try await workspace.reviewCard(card.id, rating: .good, now: now)
        let restored = try await workspace.catalog().studyCards?.first
        XCTAssertEqual(restored?.source, reference); XCTAssertEqual(restored?.memory?.reps, 1)
        XCTAssertGreaterThan(try XCTUnwrap(restored?.memory?.stability), 0)
        XCTAssertGreaterThan(try XCTUnwrap(restored?.dueAt), now)
        try await workspace.reviewCard(card.id, rating: .easy, now: try XCTUnwrap(restored?.dueAt))
        let after = try await workspace.catalog().studyCards?.first
        XCTAssertEqual(after?.memory?.reps, 2); XCTAssertEqual(after?.id, card.id)
    }
}
