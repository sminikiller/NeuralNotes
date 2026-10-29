import XCTest
@testable import NeuralNotesCore

final class SelectionArrangementTests: XCTestCase {
    func testAllAlignmentsAndEqualDimensionsPreserveIDs() {
        let a = UUID(), b = UUID(), source = [a: SnapRect(x: 20, y: 30, width: 40, height: 60), b: .init(x: 120, y: 180, width: 80, height: 20)]
        for action in SelectionArrangement.allCases where action.minimumCount == 2 {
            let result = action.applying(source), first = result[a]!, second = result[b]!
            XCTAssertEqual(Set(result.keys), Set(source.keys)); XCTAssertTrue(result.values.allSatisfy(\.valid))
            switch action {
            case .left: XCTAssertEqual(first.x, second.x)
            case .center: XCTAssertEqual(first.midX, second.midX)
            case .right: XCTAssertEqual(first.maxX, second.maxX)
            case .top: XCTAssertEqual(first.y, second.y)
            case .middle: XCTAssertEqual(first.midY, second.midY)
            case .bottom: XCTAssertEqual(first.maxY, second.maxY)
            case .width: XCTAssertEqual(first.width, second.width)
            case .height: XCTAssertEqual(first.height, second.height)
            default: break
            }
        }
    }
    func testDistributionKeepsOuterPositionsAndEqualGapsWithMixedSizes() {
        let a = UUID(), b = UUID(), c = UUID()
        let source = [a: SnapRect(x: 20, y: 10, width: 40, height: 20), b: .init(x: 83, y: 60, width: 60, height: 40), c: .init(x: 220, y: 210, width: 80, height: 60)]
        let horizontal = SelectionArrangement.horizontal.applying(source)
        XCTAssertEqual(horizontal[a]?.x, 20); XCTAssertEqual(horizontal[c]?.maxX, 300)
        XCTAssertEqual(horizontal[b]!.x - horizontal[a]!.maxX, horizontal[c]!.x - horizontal[b]!.maxX)
        let vertical = SelectionArrangement.vertical.applying(source)
        XCTAssertEqual(vertical[a]?.y, 10); XCTAssertEqual(vertical[c]?.maxY, 270)
        XCTAssertEqual(vertical[b]!.y - vertical[a]!.maxY, vertical[c]!.y - vertical[b]!.maxY)
        XCTAssertEqual(SelectionArrangement.horizontal.applying([a: source[a]!, b: source[b]!]), [a: source[a]!, b: source[b]!])
    }
}
