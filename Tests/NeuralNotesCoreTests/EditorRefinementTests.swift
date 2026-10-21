import XCTest
@testable import NeuralNotesCore

final class EditorRefinementTests: XCTestCase {
    func testBackupBudgetBoundsOverflowAndTwoProtectedVersions() {
        XCTAssertEqual(AutomaticBackupPolicy.budget(copyBytes: 1), 64 << 20)
        XCTAssertEqual(AutomaticBackupPolicy.budget(copyBytes: 100 << 20), 300 << 20)
        XCTAssertEqual(AutomaticBackupPolicy.budget(copyBytes: .max), 1 << 30)
        XCTAssertEqual(AutomaticBackupPolicy.retainedCount(sizes: [4, 4, 4, 4], maximumBytes: 12), 3)
        XCTAssertEqual(AutomaticBackupPolicy.retainedCount(sizes: [Int64.max, Int64.max, 1], maximumBytes: 1, keep: 1), 2)
    }
    func testFocusToolsAreIndependentAndBackwardCompatible() throws {
        var profile = EditorWorkspace(name: "Math", favorites: [.pen, .marker, .eraser, .ruler])
        XCTAssertEqual(profile.effectiveFocusTools, [.pen, .marker, .eraser])
        profile.focusTools = [.pen, .lasso, .ruler]; XCTAssertTrue(profile.isValid); XCTAssertEqual(profile.favorites, [.pen, .marker, .eraser, .ruler])
        let copy = try JSONDecoder().decode(EditorWorkspace.self, from: JSONEncoder().encode(profile)); XCTAssertEqual(copy.focusTools, profile.focusTools)
        profile.focusTools = [.lasso, .lasso]; XCTAssertFalse(profile.isValid)
    }
    func testLineSnapsWithinSixDegreesAndSamplesEveryPart() {
        let a = StrokeSample(x: 10, y: 20), b = StrokeSample(x: 110, y: 25)
        let snapped = PreciseLine.snappedEnd(from: a, to: b)
        XCTAssertEqual(snapped.y, a.y, accuracy: 0.00001)
        let outside = PreciseLine.snappedEnd(from: a, to: StrokeSample(x: 110, y: 40)); XCTAssertEqual(outside.y, 40)
        let diagonal = PreciseLine.snappedEnd(from: a, to: StrokeSample(x: 110, y: 115))
        XCTAssertEqual(diagonal.x - a.x, diagonal.y - a.y, accuracy: 0.00001)
        let points = PreciseLine.samples(from: a, to: snapped); XCTAssertGreaterThan(points.count, 20)
        XCTAssertEqual(points.first?.x, a.x); XCTAssertEqual(points.last?.x, snapped.x)
    }
    func testRotatedRectangleRecognizesAndRetainsItsDirection() throws {
        let angle = Double.pi / 6
        let corners = [(0.0, 0.0), (140.0, 0.0), (140.0, 80.0), (0.0, 80.0), (0.0, 0.0)]
        var points: [StrokeSample] = []
        for i in 0..<4 {
            for step in 0..<30 {
                let t = Double(step) / 30, x = corners[i].0 * (1 - t) + corners[i + 1].0 * t, y = corners[i].1 * (1 - t) + corners[i + 1].1 * t
                points.append(StrokeSample(x: 300 + x * cos(angle) - y * sin(angle), y: 200 + x * sin(angle) + y * cos(angle)))
            }
        }; points.append(points[0])
        XCTAssertEqual(HeldShapeRecognition.recognize(points), .rectangle)
        let exact = try XCTUnwrap(HeldShapeRecognition.rectangleVertices(points)); XCTAssertEqual(exact.count, 4)
        let first = exact[0], second = exact[1]; XCTAssertGreaterThan(abs(second.y - first.y), 20)
        let ellipse = (0...120).map { i in StrokeSample(x: 100 * cos(Double(i) * .pi / 60), y: 60 * sin(Double(i) * .pi / 60)) }
        XCTAssertNil(HeldShapeRecognition.rectangleVertices(ellipse))
    }
}
