import XCTest
@testable import NeuralNotesCore

final class PageDeletionTests: XCTestCase {
    private func fixture() -> PageSnapshot {
        var page = PageSnapshot()
        var text = TextElement(text: "Testo"), note = TextElement(text: "Spiegazione")
        text.pageLink = PageLinkTarget(documentID: UUID(), pageID: page.id)
        note.lensNote = LensNoteInfo(title: "Lente", source: .init(pageID: page.id, rect: .init(x: 10, y: 20, width: 30, height: 10)))
        page.texts = [text, note]
        page.images = [ImageElement(file: "images/test.png", width: 80, height: 100)]
        var a = ShapeElement(kind: .rectangle), b = ShapeElement(kind: .ellipse, x: 400)
        let anchor = StrokeAnchor(signature: "stroke", audioSessionID: UUID(), seconds: 12)
        a.audioAnchor = anchor; b.audioAnchor = anchor
        page.shapes = [a, b]
        var edge = ConnectorElement(from: .init(objectID: a.id, x: 10, y: 20), to: .init(objectID: b.id, x: 400, y: 50))
        edge.audioAnchor = anchor; page.connectors = [edge]
        page.tapes = [StudyTape()]; page.anchors = [anchor]
        page.pdfMarkups = [.init(kind: .highlight, x: 5, y: 6, width: 40, height: 15, text: "PDF"),
                           .init(kind: .underline, x: 5, y: 30, width: 40, height: 15, text: "PDF")]
        page.objectOrder = page.objectIDs; page.aboveInkObjects = page.objectIDs; page.recognizedText = "Lettura precedente"
        page.lockedObjects = [b.id]
        return page
    }
    func testEveryTypeCountsExactlyTheMetadataItRemovesAndRespectsLocks() throws {
        let page = fixture(), counts = PageDeletion.metadataCounts(in: page)
        XCTAssertEqual(counts[.text], 1); XCTAssertEqual(counts[.lensNotes], 1)
        XCTAssertEqual(counts[.shapes], 1); XCTAssertEqual(counts[.connectors], 1)
        XCTAssertEqual(counts[.images], 1); XCTAssertEqual(counts[.tapes], 1)
        XCTAssertEqual(counts[.marker], 1); XCTAssertEqual(counts[.pen], 1)
        XCTAssertEqual(counts[.audioLinks], 3)
        for kind in PageDeletionKind.allCases {
            let result = PageDeletion.removing([kind], from: page)
            XCTAssertEqual(result.id, page.id)
            XCTAssertEqual(PageDeletion.metadataCounts(in: result)[kind], 0, kind.title)
            XCTAssertEqual(result.shapes?.last?.id, page.lockedObjects?.first)
            try PageValidation.validate(result)
        }
    }
    func testDeletingAShapeDetachesItsConnectorAtItsResolvedPositionAndPreservesTheOtherTarget() throws {
        var page = fixture()
        page.refreshConnectorFallbacks(objects: page.connectorObjects())
        let start = try XCTUnwrap(page.connectors?.first?.from.point)
        let result = PageDeletion.removing([.shapes], from: page)
        XCTAssertEqual(result.connectors?.count, 1)
        XCTAssertNil(result.connectors?.first?.from.objectID)
        XCTAssertEqual(result.connectors?.first?.from.point, start)
        XCTAssertEqual(result.connectors?.first?.to.objectID, result.shapes?.first?.id)
        XCTAssertEqual(result.objectOrder?.count, page.objectOrder!.count - 1)
        XCTAssertEqual(result.aboveInkObjects?.count, page.aboveInkObjects!.count - 1)
        try PageValidation.validate(result)
    }
    func testRemovingAudioLinksKeepsContentsAndLockedAnchorsWithoutTouchingRecordings() throws {
        let page = fixture(), result = PageDeletion.removing([.audioLinks], from: page)
        XCTAssertTrue(result.anchors.isEmpty); XCTAssertNil(result.shapes?.first?.audioAnchor)
        XCTAssertEqual(result.shapes?.last?.audioAnchor, page.shapes?.last?.audioAnchor)
        XCTAssertNil(result.connectors?.first?.audioAnchor)
        XCTAssertEqual(result.texts, page.texts); XCTAssertEqual(result.images, page.images)
        XCTAssertEqual(result.recognizedText, page.recognizedText)
        XCTAssertEqual(result.objectIDs, page.objectIDs)
        try PageValidation.validate(result)
    }
    func testLensNotesAndTextAreIndependentAndEmptySelectionIsByteEquivalent() throws {
        let page = fixture()
        XCTAssertEqual(PageDeletion.removing([], from: page), page)
        let keepNotes = PageDeletion.removing([.text], from: page)
        XCTAssertEqual(keepNotes.texts, [page.texts[1]])
        let keepText = PageDeletion.removing([.lensNotes], from: page)
        XCTAssertEqual(keepText.texts, [page.texts[0]])
        XCTAssertTrue(keepText.recognizedText.isEmpty)
        XCTAssertEqual(keepText.texts.first?.pageLink, page.texts.first?.pageLink)
        let result = PageDeletion.removing(Set(PageDeletionKind.allCases), from: page)
        XCTAssertEqual(result.objectIDs, page.lockedObjects)
        try PageValidation.validate(result)
    }
}
