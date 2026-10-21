import XCTest
@testable import NeuralNotesCore

final class MindMapLayoutTests: XCTestCase {
    func testNativeMapRetainsOutlineTextEditableNodesAndExplicitSourceLinks() throws {
        let source = SourceReference(documentID: UUID(), pageID: UUID())
        let artifact = AIArtifact(text: "# Energia\n- Definizione [1]\n- Conservazione [1]", references: [source], provider: "fixture", task: .outline)
        let page = try XCTUnwrap(MindMapLayout.page(from: artifact))
        XCTAssertEqual(page.texts.map(\.text), ["Energia", "Definizione [1]", "Conservazione [1]"])
        XCTAssertEqual(page.shapes?.count, 2); XCTAssertTrue(page.images.isEmpty)
        XCTAssertEqual(page.texts[1].pageLink, PageLinkTarget(documentID: source.documentID, pageID: source.pageID!))
        XCTAssertNoThrow(try PageValidation.validate(page))
        XCTAssertEqual(Set(page.objectIDs).count, page.objectIDs.count)
    }
    func testMapIsBoundedAndNeverInventsALinkForAnUncitedLine() throws {
        let text = "Titolo\n" + (0..<30).map { "Punto \($0)" }.joined(separator: "\n")
        let page = try XCTUnwrap(MindMapLayout.page(from: AIArtifact(text: text, references: [], provider: "fixture"), width: 768, height: 1024))
        XCTAssertEqual(page.texts.count, 9); XCTAssertTrue(page.texts.allSatisfy { $0.pageLink == nil && $0.x >= 0 && $0.x + $0.width <= page.width && $0.y < page.height })
        XCTAssertNil(MindMapLayout.page(from: AIArtifact(text: "Solo titolo", references: [], provider: "fixture")))
    }
}
