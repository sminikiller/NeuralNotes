import XCTest
@testable import NeuralNotesCore

final class StudyKitTests: XCTestCase {
    func testLegacyTapeDecodesAndNewMetadataRoundTrips() throws {
        let old = """
        {"id":"DD1CA0B8-71FC-4A04-91A7-A8275860DE96","x":12,"y":24,"width":120,"height":32,"revealed":false}
        """
        var tape = try JSONDecoder().decode(StudyTape.self, from: Data(old.utf8))
        XCTAssertNil(tape.color); XCTAssertNil(tape.style)
        tape.color = .mint; tape.style = .striped
        var page = PageSnapshot(); page.tapes = [tape]
        var note = TextElement(text: "Da ricordare"); note.studyNote = StudyNoteInfo(kind: .question, collapsed: true)
        page.texts = [note]
        let decoded = try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(decoded, page); try PageValidation.validate(decoded)
        var section = NotebookSection(title: "Anatomia", pageIDs: [page.id]); section.color = .pink
        XCTAssertEqual(try JSONDecoder().decode(NotebookSection.self, from: JSONEncoder().encode(section)), section)
    }
    func testEveryDiagramStaysInsidePaperWithValidConnectedObjects() throws {
        for template in StudyDiagramTemplate.allCases {
            for size in [(240.0, 320.0), (768.0, 1024.0), (1024.0, 768.0)] {
                let diagram = try XCTUnwrap(StudyDiagrams.make(template, width: size.0, height: size.1))
                var page = PageSnapshot(); page.width = size.0; page.height = size.1
                page.shapes = diagram.shapes; page.connectors = diagram.connectors
                try PageValidation.validate(page)
                let ids = Set(diagram.shapes.map(\.id))
                XCTAssertEqual(diagram.connectors.count, diagram.shapes.count - 1)
                for edge in diagram.connectors { XCTAssertTrue(ids.contains(try XCTUnwrap(edge.from.objectID))); XCTAssertTrue(ids.contains(try XCTUnwrap(edge.to.objectID))) }
                for shape in diagram.shapes {
                    XCTAssertGreaterThanOrEqual(shape.x, 0); XCTAssertGreaterThanOrEqual(shape.y, 0)
                    XCTAssertLessThanOrEqual(shape.x + shape.width, page.width)
                    XCTAssertLessThanOrEqual(shape.y + shape.height, page.height)
                }
                let originalIDs = Set(page.objectIDs); page.renewObjectIDs()
                XCTAssertTrue(originalIDs.isDisjoint(with: page.objectIDs))
                for edge in page.connectors ?? [] { XCTAssertTrue(page.connectorTargetIDs.contains(try XCTUnwrap(edge.from.objectID))) }
            }
        }
    }
    func testOutlinePreservesParentageAndBoundsLargeInputs() throws {
        let outline = StudyDiagrams.outline("• Organi\n  Cuore\n  Polmoni\n• Tessuti\n  Epitelio", title: "Anatomia")
        XCTAssertEqual(outline.labels, ["Anatomia", "Organi", "Cuore", "Polmoni", "Tessuti", "Epitelio"])
        XCTAssertEqual(outline.parents, [0, 0, 1, 1, 0, 4])
        let diagram = try XCTUnwrap(StudyDiagrams.make(.mindMap, labels: outline.labels, width: 768, height: 1024, parents: outline.parents))
        XCTAssertEqual(diagram.connectors[1].from.objectID, diagram.shapes[1].id)
        let many = StudyDiagrams.outline(Array(repeating: "voce", count: 1000).joined(separator: "\n"), title: "Test")
        XCTAssertEqual(many.labels.count, 16)
        XCTAssertNil(StudyDiagrams.make(.mindMap, width: .nan, height: 1024))
    }
    func testExportChoiceDoesNotMutateOriginalAndDropsOnlyTapeReferences() {
        var page = PageSnapshot(); var tape = StudyTape(); tape.revealed = true; tape.style = .translucent
        page.tapes = [tape]; let note = TextElement(text: "Risposta"); page.texts = [note]
        page.objectOrder = [note.id, tape.id]; page.lockedObjects = [tape.id]
        let covered = StudyTapeExport.covered.applying(to: page)
        XCTAssertEqual(covered.tapes?.first?.revealed, false); XCTAssertEqual(covered.tapes?.first?.style, .solid)
        let answers = StudyTapeExport.answers.applying(to: page)
        XCTAssertEqual(answers.tapes, []); XCTAssertEqual(answers.texts, [note]); XCTAssertEqual(answers.objectOrder, [note.id])
        XCTAssertEqual(page.tapes?.first, tape)
    }
}
