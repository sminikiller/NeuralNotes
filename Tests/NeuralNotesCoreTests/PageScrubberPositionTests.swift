import XCTest
@testable import NeuralNotesCore

final class PageScrubberPositionTests: XCTestCase {
    func testEmptySingleAndLargeDocumentsReachBothEnds() {
        XCTAssertNil(PageScrubberPosition.index(fraction: 0.5, count: 0))
        XCTAssertNil(PageScrubberPosition.index(fraction: 0.5, count: -1))
        for fraction in [-3.0, 0, 0.5, 1, 4] {
            XCTAssertEqual(PageScrubberPosition.index(fraction: fraction, count: 1), 0)
        }
        XCTAssertEqual(PageScrubberPosition.index(fraction: -1, count: 1500), 0)
        XCTAssertEqual(PageScrubberPosition.index(fraction: 1.3, count: 1500), 1499)
        XCTAssertEqual(PageScrubberPosition.index(fraction: 0.5, count: 1500), 750)
        XCTAssertNil(PageScrubberPosition.index(fraction: .nan, count: 10))
        XCTAssertNil(PageScrubberPosition.index(fraction: .infinity, count: 10))
    }

    func testEveryPageRoundTripsWithoutOffByOneErrors() {
        for count in [1, 2, 6, 12, 300, 1500] {
            for index in 0..<count {
                let fraction = PageScrubberPosition.fraction(index: index, count: count)
                XCTAssertEqual(PageScrubberPosition.index(fraction: fraction, count: count), index)
            }
        }
        XCTAssertEqual(PageScrubberPosition.fraction(index: -100, count: 12), 0)
        XCTAssertEqual(PageScrubberPosition.fraction(index: 100, count: 12), 1)
        XCTAssertEqual(PageScrubberPosition.fraction(index: 2, count: 0), 0)
    }

    func testJumpRejectsInvalidNumbersInsteadOfOpeningAnotherPage() {
        for value in ["", "0", "-1", "1501", "1.5", "abc", "9999999999999999999999999"] {
            XCTAssertNil(PageScrubberPosition.pageNumber(value, count: 1500), value)
        }
        XCTAssertEqual(PageScrubberPosition.pageNumber(" 1\n", count: 1500), 0)
        XCTAssertEqual(PageScrubberPosition.pageNumber("1500", count: 1500), 1499)
        XCTAssertNil(PageScrubberPosition.pageNumber("1", count: 0))
    }
}
