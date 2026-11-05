import XCTest

extension XCTestCase {
    /// List cells are virtualized. A full-height inertial swipe can jump over a
    /// short destination row after another preference is inserted above it.
    /// Use short, settled drags and still require the real row to be tappable.
    @MainActor func revealWorkspaceRow(_ row: XCUIElement, in list: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(list.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<20 {
            if row.exists && row.isHittable { break }
            let start = list.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.78))
            let end = list.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.60))
            start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(row.isHittable, file: file, line: line)
    }
}
