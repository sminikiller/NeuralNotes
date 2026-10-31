import XCTest
@testable import NeuralNotesCore

final class EraserTargetTests: XCTestCase {
    func testLegacyMarkerOnlyAndFutureTargetDecodeWithoutLosingWritingPreferences() throws {
        var options = WritingOptions(); options.markerOnly = true; options.eraserWidth = 22
        let legacy = try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(legacy.effectiveEraserTarget, .marker); XCTAssertNil(legacy.eraserTarget)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        json["eraserTarget"] = "futureKind"
        let future = try JSONDecoder().decode(WritingOptions.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(future.effectiveEraserTarget, .marker); XCTAssertEqual(future.eraserWidth, 22)
        for target in EraserTarget.allCases {
            options.eraserTarget = target
            XCTAssertEqual(try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options)), options)
        }
    }
    func testSpatialQueriesFindThinCrossingBoxesAndExcludeNearbyUntouchedObjects() {
        let crossing = UUID(), nearby = UUID(), large = UUID()
        let index = EraserSpatialIndex(boxes: [crossing: .init(x: 10, y: 90, width: 200, height: 1),
            nearby: .init(x: 300, y: 30, width: 20, height: 20), large: .init(x: -1000, y: -1000, width: 5000, height: 5000)])
        XCTAssertEqual(index.candidates(in: .init(x: 99, y: 0, width: 2, height: 180)), [crossing, large])
        XCTAssertEqual(index.candidates(in: .init(x: 290, y: 20, width: 40, height: 40)), [nearby, large])
        XCTAssertTrue(index.candidates(in: .init(x: .nan, y: 0, width: 1, height: 1)).isEmpty)
    }
    func testLargeQueriesUseBoundedBoxScanAndMatchASimpleIntersectionOracle() {
        var boxes: [UUID: SnapRect] = [:]
        for i in 0..<2000 { boxes[UUID()] = .init(x: Double(i % 50) * 35, y: Double(i / 50) * 35, width: 25, height: 25) }
        let index = EraserSpatialIndex(boxes: boxes)
        for query in [SnapRect(x: -100, y: -100, width: 20000, height: 20000), .init(x: 275, y: 341, width: 80, height: 70)] {
            let expected = Set(boxes.filter { _, b in b.x <= query.maxX && b.maxX >= query.x && b.y <= query.maxY && b.maxY >= query.y }.keys)
            XCTAssertEqual(index.candidates(in: query), expected)
        }
    }
}
