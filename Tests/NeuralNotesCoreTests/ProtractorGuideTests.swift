import XCTest
@testable import NeuralNotesCore

final class ProtractorGuideTests: XCTestCase {
    func testArcProjectionUsesPageCoordinatesAndKeepsTheRadiusAtEveryRotation() throws {
        for rotation in [-Double.pi, -0.37, 0, 0.6, Double.pi * 1.5] {
            let guide = ProtractorGuide(x: 320, y: 410, radius: 170, rotation: rotation, kind: .circle)
            for degree in stride(from: 0, to: 360, by: 7) {
                let expected = Double(degree) * .pi / 180
                let candidate = try XCTUnwrap(guide.point(at: expected, distance: 188))
                let projected = try XCTUnwrap(guide.project(candidate, mode: .arc))
                XCTAssertEqual(hypot(projected.x - guide.x, projected.y - guide.y), 170, accuracy: 1e-8)
                let measured = try XCTUnwrap(guide.angle(at: projected))
                XCTAssertEqual(try XCTUnwrap(ProtractorGuide.difference(measured, expected)), 0, accuracy: 1e-8)
            }
        }
    }
    func testSemicircleClampsToItsEndpointsInsteadOfDrawingItsHiddenHalf() throws {
        let guide = ProtractorGuide(x: 300, y: 300, radius: 160)
        XCTAssertEqual(try XCTUnwrap(guide.angle(at: .init(x: 450, y: 320))), 0, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(guide.angle(at: .init(x: 150, y: 320))), .pi, accuracy: 1e-8)
        XCTAssertEqual(guide.mode(at: .init(x: 300, y: 460), zoom: 1), nil)
        XCTAssertEqual(guide.mode(at: .init(x: 300, y: 140), zoom: 1), .arc)
    }
    func testAcquisitionThresholdIsTwelveScreenPointsAndCenterChoosesRay() {
        let guide = ProtractorGuide(x: 300, y: 300, radius: 160)
        XCTAssertEqual(guide.mode(at: .init(x: 467, y: 300), zoom: 1), .arc)
        XCTAssertNil(guide.mode(at: .init(x: 467, y: 300), zoom: 2))
        XCTAssertEqual(guide.mode(at: .init(x: 300, y: 305), zoom: 2), .ray)
        XCTAssertNil(guide.mode(at: .init(x: 300, y: 305), zoom: 0))
    }
    func testRaySnapsToMajorAnglesWithoutChangingItsDistance() throws {
        let guide = ProtractorGuide(x: 300, y: 300, rotation: 0.4, kind: .circle)
        for degrees in [5.0, 15, 30, 45, 90, 180, 270, 355] {
            let candidate = try XCTUnwrap(guide.point(at: (degrees + 0.7) * .pi / 180, distance: 122))
            let projected = try XCTUnwrap(guide.project(candidate, mode: .ray))
            XCTAssertEqual(hypot(projected.x - guide.x, projected.y - guide.y), 122, accuracy: 1e-8)
            XCTAssertEqual(try XCTUnwrap(guide.angle(at: projected)), degrees * .pi / 180, accuracy: 1e-8)
        }
        XCTAssertEqual(try XCTUnwrap(ProtractorGuide.difference(350 * .pi / 180, 10 * .pi / 180)), 20 * .pi / 180, accuracy: 1e-8)
    }
    func testMeasurementsAndInvalidNumbers() throws {
        let far = try XCTUnwrap(ProtractorGuide(x: 0, y: 0).point(at: 0, distance: 28000))
        XCTAssertEqual(far.x, 28000, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(ProtractorGuide.centimeters(points: 72)), 2.54, accuracy: 1e-10)
        XCTAssertNil(ProtractorGuide.centimeters(points: .infinity))
        XCTAssertNil(ProtractorGuide(x: .nan).project(.init(x: 1, y: 2), mode: .arc))
        XCTAssertNil(ProtractorGuide(radius: 0).mode(at: .init(x: 1, y: 2), zoom: 1))
        XCTAssertNil(ProtractorGuide().point(at: .infinity))
        XCTAssertEqual(try JSONDecoder().decode(ProtractorGuide.Kind.self, from: Data("\"future\"".utf8)), .semicircle)
    }
}
