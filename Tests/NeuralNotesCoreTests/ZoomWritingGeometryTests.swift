import XCTest
@testable import NeuralNotesCore

final class ZoomWritingGeometryTests: XCTestCase {
    func testWritingCoordinatesRoundTripAtEverySupportedZoom() throws {
        for zoom in [2.0, 2.5, 3, 4] {
            var window = try XCTUnwrap(ZoomWritingGeometry(pageWidth: 600, pageHeight: 800, panelWidth: 900, panelHeight: 240, zoom: zoom))
            window.move(to: .init(x: 80, y: 200))
            let point = StrokeSample(x: 150, y: 83)
            let page = try XCTUnwrap(window.pagePoint(fromPanel: point))
            let back = try XCTUnwrap(window.panelPoint(fromPage: page))
            XCTAssertEqual(back.x, point.x, accuracy: 0.00001); XCTAssertEqual(back.y, point.y, accuracy: 0.00001)
            XCTAssertEqual(page.x, window.x + point.x / zoom, accuracy: 0.00001)
        }
    }
    func testAutomaticAdvanceWaitsForTheLastFifteenPercentThenClampsAndUsesRulingForNewLine() throws {
        var window = try XCTUnwrap(ZoomWritingGeometry(pageWidth: 600, pageHeight: 800, panelWidth: 600, panelHeight: 240))
        let first = window
        window.advance(after: .init(x: first.x + first.width * 0.8, y: 50), lineSpacing: 32)
        XCTAssertEqual(window, first)
        window.advance(after: .init(x: first.x + first.width * 0.86, y: 50), lineSpacing: 32)
        XCTAssertGreaterThan(window.x, first.x); XCTAssertEqual(window.y, 0)
        for _ in 0..<10 where window.y == 0 { window.advance(after: .init(x: window.x + window.width, y: 50), lineSpacing: 32) }
        XCTAssertEqual(window.y, 32); XCTAssertEqual(window.x, 24)
        window.move(to: .init(x: 50_000, y: 50_000)); window.newLine(spacing: 32)
        XCTAssertTrue(window.atEnd); XCTAssertEqual(window.y + window.height, 800)
    }
    func testMarginsAndResizeCannotPutWindowOutsidePageOrAcceptInvalidValues() throws {
        XCTAssertNil(ZoomWritingGeometry(pageWidth: 600, pageHeight: 800, panelWidth: .infinity, panelHeight: 240))
        var window = try XCTUnwrap(ZoomWritingGeometry(pageWidth: 600, pageHeight: 800, panelWidth: 600, panelHeight: 240))
        window.move(to: .init(x: 400, y: 750)); window.resize(panelWidth: 900, panelHeight: 300, zoom: 2)
        XCTAssertLessThanOrEqual(window.x + window.width, 576); XCTAssertLessThanOrEqual(window.y + window.height, 800)
        window.margins(left: 40, right: 50); XCTAssertGreaterThanOrEqual(window.x, 40); XCTAssertLessThanOrEqual(window.x + window.width, 550)
        let before = window; window.margins(left: 500, right: 500); window.resize(panelWidth: .nan, panelHeight: 200, zoom: 3)
        XCTAssertEqual(window, before); XCTAssertNil(window.pagePoint(fromPanel: .init(x: .nan, y: 0)))
    }
}
