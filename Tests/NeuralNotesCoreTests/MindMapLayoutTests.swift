import XCTest
@testable import NeuralNotesCore

final class MindMapLayoutTests: XCTestCase {
    func testNativeMapRetainsOutlineTextEditableNodesAndExplicitSourceLinks() throws {
        let source = SourceReference(documentID: UUID(), pageID: UUID())
        let artifact = AIArtifact(text: "# Energia\n- Definizione [1]\n- Conservazione [1]", references: [source], provider: "fixture", task: .outline)
        let page = try XCTUnwrap(MindMapLayout.page(from: artifact))
        XCTAssertEqual(page.shapes?.compactMap(\.label), ["Energia", "Definizione [1]", "Conservazione [1]"])
        XCTAssertEqual(page.connectors?.count, 2); XCTAssertTrue(page.images.isEmpty); XCTAssertTrue(page.texts.isEmpty)
        XCTAssertEqual(page.shapes?[1].pageLink, PageLinkTarget(documentID: source.documentID, pageID: source.pageID!))
        for edge in page.connectors ?? [] {
            XCTAssertEqual(edge.routing, .curved); XCTAssertEqual(edge.from.objectID, page.shapes?.first?.id)
            XCTAssertTrue((page.shapes ?? []).contains { $0.id == edge.to.objectID })
        }
        XCTAssertNoThrow(try PageValidation.validate(page))
        XCTAssertEqual(Set(page.objectIDs).count, page.objectIDs.count)
    }
    func testMapIsBoundedAndNeverInventsALinkForAnUncitedLine() throws {
        let text = "Titolo\n" + (0..<30).map { "Punto \($0)" }.joined(separator: "\n")
        let page = try XCTUnwrap(MindMapLayout.page(from: AIArtifact(text: text, references: [], provider: "fixture"), width: 768, height: 1024))
        let blocks = page.shapes ?? []
        XCTAssertEqual(blocks.count, 9); XCTAssertEqual(page.connectors?.count, 8)
        XCTAssertTrue(blocks.allSatisfy { $0.pageLink == nil && $0.x >= 0 && $0.x + $0.width <= page.width && $0.y + $0.height <= page.height && $0.cornerRadius != nil })
        for i in blocks.indices { for j in blocks.indices where j > i {
            let a = blocks[i], b = blocks[j]
            XCTAssertFalse(a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y)
        } }
        XCTAssertNil(MindMapLayout.page(from: AIArtifact(text: "Solo titolo", references: [], provider: "fixture")))
    }
}
