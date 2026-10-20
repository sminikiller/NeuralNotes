import XCTest
@testable import NeuralNotesCore

final class ContinuousPageLayoutTests: XCTestCase {
    func testDifferentPaperSizesShareOneContinuousStripWithSmallExactGaps() throws {
        var a = PageSnapshot(), b = PageSnapshot(), c = PageSnapshot()
        a.width = 600; a.height = 800; b.width = 800; b.height = 600; c.width = 600; c.height = 900
        let layout = ContinuousPageLayout(pages: [a, b, c])
        let first = try XCTUnwrap(layout.frame(a.id)), second = try XCTUnwrap(layout.frame(b.id)), third = try XCTUnwrap(layout.frame(c.id))
        XCTAssertEqual(layout.width, 800); XCTAssertEqual(layout.maximumPageHeight, 900)
        XCTAssertEqual(first.x, 100); XCTAssertEqual(second.x, 0)
        XCTAssertEqual(second.y - first.maxY, 12); XCTAssertEqual(third.y - second.maxY, 12)
        XCTAssertEqual(layout.height, 2324)
        XCTAssertEqual(layout.page(atX: 200, y: 100), a.id)
        XCTAssertNil(layout.page(atX: 200, y: 805))
        XCTAssertEqual(layout.page(atX: 400, y: 900), b.id)
    }
    func testVisiblePageFollowsViewportWithoutQuantizingTheOffset() {
        let pages = (0..<3).map { _ in PageSnapshot() }
        let layout = ContinuousPageLayout(pages: pages)
        XCTAssertEqual(layout.mostVisible(top: 150, height: 700), pages[0].id)
        XCTAssertEqual(layout.mostVisible(top: 1000, height: 700), pages[1].id)
        XCTAssertEqual(layout.mostVisible(top: 2200, height: 700), pages[2].id)
        XCTAssertNil(layout.mostVisible(top: 10000, height: 700))
        XCTAssertNil(layout.mostVisible(top: .nan, height: 700))
    }
    func testLayoutHandlesEmptyInvalidGeometryAndLongDocumentsWithoutChangingOrder() {
        var bad = PageSnapshot(); bad.height = .infinity
        let pages = (0..<1000).map { _ in PageSnapshot() }
        let layout = ContinuousPageLayout(pages: [bad] + pages)
        XCTAssertEqual(layout.frames.map(\.id), pages.map(\.id))
        XCTAssertTrue(layout.height.isFinite); XCTAssertEqual(layout.frames.count, 1000)
        XCTAssertEqual(ContinuousPageLayout(pages: []).height, 0)
    }
}
