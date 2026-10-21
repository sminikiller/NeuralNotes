import XCTest
@testable import NeuralNotesCore

final class PreviewBudgetTests: XCTestCase {
    func testLargeCompressedAndHighlyExpandedDrawingsDoNotStayInPrefetch() {
        XCTAssertFalse(PreviewBudget.canRetainDrawing(encodedBytes: 9 * 1024 * 1024, controlPoints: 10, imageBytes: 1))
        XCTAssertFalse(PreviewBudget.canRetainDrawing(encodedBytes: 1000, controlPoints: 1_000_000, imageBytes: 4 * 1024 * 1024))
        XCTAssertTrue(PreviewBudget.canRetainDrawing(encodedBytes: 1000, controlPoints: 100, imageBytes: 4 * 1024 * 1024))
    }
    func testOverflowAndNegativeAccountingCannotBypassTheBudget() {
        XCTAssertEqual(PreviewBudget.drawingCost(encodedBytes: 1, controlPoints: Int.max), Int.max)
        XCTAssertFalse(PreviewBudget.canRetainDrawing(encodedBytes: -1, controlPoints: 10, imageBytes: 1))
        XCTAssertFalse(PreviewBudget.canRetainDrawing(encodedBytes: 1, controlPoints: 10, imageBytes: Int.max))
    }
}
