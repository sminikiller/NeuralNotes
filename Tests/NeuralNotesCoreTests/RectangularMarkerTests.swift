import XCTest
@testable import NeuralNotesCore

final class RectangularMarkerTests: XCTestCase {
    func testRectangleSurvivesNativeCodingAndIsCountedOnceOnlyAsMarker() throws {
        let marker = try XCTUnwrap(RectangularMarker.make(CGRect(x: 10, y: 20, width: 120, height: 30), color: .yellow))
        var page = PageSnapshot(); page.shapes = [marker, ShapeElement(kind: .ellipse)]
        try PageValidation.validate(page)
        let reopened = try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(page, reopened)
        XCTAssertEqual(PageDeletion.metadataCounts(in: page)[.marker], 1)
        XCTAssertEqual(PageDeletion.metadataCounts(in: page)[.shapes], 1)
        XCTAssertEqual(PageDeletion.removing([.marker], from: page).shapes?.count, 1)
        XCTAssertEqual(PageDeletion.removing([.shapes], from: page).shapes, [marker])
        page.lockedObjects = [marker.id]
        XCTAssertEqual(PageDeletion.metadataCounts(in: page)[.marker], 0)
        XCTAssertEqual(PageDeletion.removing([.marker], from: page), page)
    }
    func testMarkerValidationStyleAndLegacyOptionDecoding() throws {
        var marker = try XCTUnwrap(RectangularMarker.make(CGRect(x: 0, y: 0, width: 20, height: 10), color: .green))
        var style = ShapeStyle(); style.fill = .blue; style.fillOpacity = 0.4; style.strokeOpacity = 1; style.cornerRadius = 10
        marker = style.applying(to: marker)
        XCTAssertEqual(marker.fill, .blue); XCTAssertEqual(marker.strokeOpacity, 0); XCTAssertEqual(marker.cornerRadius, 0)
        XCTAssertTrue(marker.hasValidOptions)
        marker.kind = .star; XCTAssertFalse(marker.hasValidOptions)
        XCTAssertNil(RectangularMarker.make(CGRect(x: 0, y: 0, width: 0, height: 10), color: .yellow))
        var options = WritingOptions(); options.markerSnapWords = false
        let reopened = try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(reopened.effectiveMarkerMode, .freehand)
        options.markerMode = .rectangle
        XCTAssertEqual(try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options)).effectiveMarkerMode, .rectangle)
    }
    func testTextSnappingKeepsLinesAndColumnsSeparate() {
        let words = [PageWord(text: "One", rect: CGRect(x: 10, y: 10, width: 20, height: 12)),
            PageWord(text: "two", rect: CGRect(x: 35, y: 10, width: 25, height: 12)),
            PageWord(text: "Column", rect: CGRect(x: 160, y: 10, width: 40, height: 12)),
            PageWord(text: "Next", rect: CGRect(x: 10, y: 40, width: 40, height: 12)),
            PageWord(text: "Outside", rect: CGRect(x: 10, y: 90, width: 40, height: 12))]
        let lines = RectangularMarker.snapped(CGRect(x: 0, y: 0, width: 220, height: 60), words: words)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], CGRect(x: 8.5, y: 8.5, width: 53, height: 15))
        XCTAssertEqual(lines[1].minX, 158.5); XCTAssertEqual(lines[2].minY, 38.5)
    }
}
