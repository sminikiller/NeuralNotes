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

final class LensPlacementTests: XCTestCase {
    func testAnswerGoesBesideTheSelectionAndStaysOnThePage() {
        let selection = CGRect(x: 60, y: 200, width: 200, height: 40)
        let rect = LensGeometry.placement(text: "Risposta breve", near: selection, occupied: [selection], pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(rect.minX, 276); XCTAssertEqual(rect.minY, 200); XCTAssertEqual(rect.width, 360)
        XCTAssertFalse(rect.intersects(selection))
        // No room on the right: the answer moves below the selection, inside the margins.
        let wide = CGRect(x: 40, y: 300, width: 700, height: 30)
        let below = LensGeometry.placement(text: "Risposta", near: wide, occupied: [], pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(below.minY, 342); XCTAssertLessThanOrEqual(below.maxX, 744); XCTAssertGreaterThanOrEqual(below.minX, 24)
        // At the bottom of the page it goes above, never off the page or over the selection.
        let low = CGRect(x: 30, y: 960, width: 720, height: 40)
        let above = LensGeometry.placement(text: "Testo", near: low, occupied: [], pageWidth: 768, pageHeight: 1024)
        XCTAssertFalse(above.intersects(low)); XCTAssertLessThan(above.maxY, low.minY); XCTAssertGreaterThanOrEqual(above.minY, 24)
    }

    func testOtherNotesAreAvoidedWhenAFreeSpotExists() {
        let selection = CGRect(x: 60, y: 200, width: 200, height: 40), note = CGRect(x: 280, y: 180, width: 400, height: 120)
        let rect = LensGeometry.placement(text: "Risposta", near: selection, occupied: [note], pageWidth: 768, pageHeight: 1024)
        XCTAssertFalse(rect.intersects(note)); XCTAssertFalse(rect.intersects(selection))
        // Without a selection the first free band below existing notes is used.
        let header = CGRect(x: 40, y: 40, width: 600, height: 200)
        let free = LensGeometry.placement(text: "Risposta", near: nil, occupied: [header], pageWidth: 768, pageHeight: 1024)
        XCTAssertGreaterThan(free.minY, header.maxY); XCTAssertEqual(free.minX, 48)
        // A full page still returns a valid rectangle inside the page.
        let full = LensGeometry.placement(text: "Risposta", near: nil, occupied: [CGRect(x: 0, y: 0, width: 768, height: 1024)], pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(full.minY, 64); XCTAssertTrue(CGRect(x: 0, y: 0, width: 768, height: 1024).contains(full))
    }

    func testLongAnswersGrowButFitAndSmallPagesNarrowTheBox() {
        let text = String(repeating: "parola ", count: 400)
        let size = LensGeometry.answerSize(text: text, fontSize: 16, width: 360)
        XCTAssertGreaterThan(size.height, 400)
        let rect = LensGeometry.placement(text: text, near: nil, occupied: [], pageWidth: 300, pageHeight: 400)
        XCTAssertEqual(rect.width, 252); XCTAssertLessThanOrEqual(rect.maxY, 376); XCTAssertGreaterThanOrEqual(rect.minY, 24)
        XCTAssertEqual(LensGeometry.answerSize(text: "a\nb\nc", fontSize: 10, width: 200).height, 3 * 10 * 1.35 + 16, accuracy: 0.001)
    }
}
