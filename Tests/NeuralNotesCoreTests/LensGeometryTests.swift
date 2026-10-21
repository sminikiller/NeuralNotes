import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import NeuralNotesCore

final class LensGeometryTests: XCTestCase {
    func testFractionalCoordinatesAreNotRoundedAndAreClippedToThePage() throws {
        let box = try XCTUnwrap(LensGeometry.selection(from: StrokeSample(x: -2.75, y: 3.25), to: StrokeSample(x: 40.5, y: 60.75), pageWidth: 35.25, pageHeight: 70.5))
        XCTAssertEqual(box.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(box.minY, 3.25, accuracy: 0.0001)
        XCTAssertEqual(box.width, 35.25, accuracy: 0.0001)
        XCTAssertEqual(box.height, 57.5, accuracy: 0.0001)
    }
    func testClosedCircleUsesTheEntireTraceAndAReversedUnderlineStillSelectsAbove() throws {
        let circle = [StrokeSample(x: 100, y: 100), StrokeSample(x: 150, y: 50), StrokeSample(x: 200, y: 100), StrokeSample(x: 150, y: 150), StrokeSample(x: 100, y: 100)]
        let area = try XCTUnwrap(LensGeometry.selection(trace: circle, pageWidth: 768, pageHeight: 1024))
        XCTAssertEqual(area, CGRect(x: 100, y: 50, width: 100, height: 100))
        let underline = [StrokeSample(x: 200, y: 100), StrokeSample(x: 150, y: 98), StrokeSample(x: 100, y: 100)]
        let above = try XCTUnwrap(LensGeometry.selection(trace: underline, pageWidth: 768, pageHeight: 1024))
        XCTAssertLessThan(above.minY, 98); XCTAssertTrue(above.contains(CGPoint(x: 150, y: 90)))
        XCTAssertNil(LensGeometry.selection(trace: [], pageWidth: 768, pageHeight: 1024))
        XCTAssertNil(LensGeometry.selection(trace: [StrokeSample(x: .nan, y: 0)], pageWidth: 768, pageHeight: 1024))
    }
    func testUnderlineSelectsAboveTheGestureAndClampsToThePage() throws {
        let box = try XCTUnwrap(LensGeometry.selection(from: StrokeSample(x: 20, y: 100), to: StrokeSample(x: 120, y: 102), pageWidth: 200, pageHeight: 300))
        XCTAssertLessThan(box.minY, 80); XCTAssertGreaterThan(box.maxY, 102); XCTAssertGreaterThan(box.width, 100)
        let edge = try XCTUnwrap(LensGeometry.selection(from: StrokeSample(x: -10, y: 5), to: StrokeSample(x: 220, y: 5), pageWidth: 200, pageHeight: 300))
        XCTAssertEqual(edge.minX, 0); XCTAssertEqual(edge.minY, 0); XCTAssertEqual(edge.width, 200)
    }
    func testNormalAreaKeepsItsGeometryAndInvalidGesturesAreIgnored() throws {
        let box = try XCTUnwrap(LensGeometry.selection(from: StrokeSample(x: 100, y: 150), to: StrokeSample(x: 20, y: 30), pageWidth: 200, pageHeight: 300))
        XCTAssertEqual(box, CGRect(x: 20, y: 30, width: 80, height: 120))
        XCTAssertNil(LensGeometry.selection(from: StrokeSample(x: 1, y: 1), to: StrokeSample(x: 1, y: 1), pageWidth: 200, pageHeight: 300))
        XCTAssertNil(LensGeometry.selection(from: StrokeSample(x: .nan, y: 1), to: StrokeSample(x: 20, y: 1), pageWidth: 200, pageHeight: 300))
    }
}
