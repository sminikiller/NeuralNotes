import XCTest
@testable import NeuralNotesCore

final class PerspectiveQuadTests: XCTestCase {
    func testFullAndOppositeSideAverages() throws {
        XCTAssertTrue(PerspectiveQuad.full.isConvex)
        XCTAssertEqual(PerspectiveQuad.full.outputSize(for: .init(width: 1200, height: 800)), .init(width: 1200, height: 800))
        let quad = PerspectiveQuad(topLeft: .init(x: 0.1, y: 0.1), topRight: .init(x: 0.8, y: 0.1),
            bottomRight: .init(x: 0.9, y: 0.9), bottomLeft: .init(x: 0.1, y: 0.9))
        let size = try XCTUnwrap(quad.outputSize(for: .init(width: 1000, height: 500)))
        XCTAssertEqual(size.width, 750, accuracy: 0.001)
        XCTAssertEqual(size.height, (400 + hypot(100, 400)) / 2, accuracy: 0.001)
    }
    func testOrderingAllPermutationsAndRejectingBowTieConcaveAndNonFinite() {
        let points = PerspectiveQuad.full.points
        for a in 0..<4 { for b in 0..<4 where b != a { for c in 0..<4 where c != a && c != b {
            let d = (0..<4).first { $0 != a && $0 != b && $0 != c }!
            let shuffled = PerspectiveQuad(topLeft: points[a], topRight: points[b], bottomRight: points[c], bottomLeft: points[d])
            XCTAssertEqual(shuffled.ordered(), .full)
        } } }
        var invalid = PerspectiveQuad.full
        invalid.topLeft = .init(x: .nan, y: 0); XCTAssertFalse(invalid.isConvex)
        invalid.topLeft = .init(x: -0.01, y: 0); XCTAssertFalse(invalid.isConvex)
        invalid = .full; invalid.topRight = invalid.bottomLeft; XCTAssertFalse(invalid.isConvex)
        invalid = .full; invalid.topRight = .init(x: 0.2, y: 0.8); XCTAssertFalse(invalid.isConvex)
        let bow = PerspectiveQuad(topLeft: points[0], topRight: points[2], bottomRight: points[1], bottomLeft: points[3])
        XCTAssertFalse(bow.isConvex)
        XCTAssertNil(bow.outputSize(for: .init(width: 100, height: 100)))
        XCTAssertNil(PerspectiveQuad.full.outputSize(for: .init(width: 0, height: 100)))
    }
    func testLegacyImagesDecodeAndAdjustedPagesValidateWithoutChangingOriginal() throws {
        var page = PageSnapshot()
        let image = ImageElement(file: "images/original.jpg", width: 200, height: 300)
        page.images = [image]
        let legacy = try JSONEncoder().encode(page)
        XCTAssertNil(try JSONDecoder().decode(PageSnapshot.self, from: legacy).images.first?.perspective)
        page.images[0].perspective = .full; page.images[0].photoQuarterTurns = 3; page.images[0].photoEnhanced = true
        try PageValidation.validate(page)
        let restored = try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(restored, page); XCTAssertEqual(restored.images[0].file, image.file)
        page.images[0].photoQuarterTurns = 4; XCTAssertThrowsError(try PageValidation.validate(page))
        page.images[0].photoQuarterTurns = 0
        page.images[0].perspective?.topLeft.x = .infinity; XCTAssertThrowsError(try PageValidation.validate(page))
    }
}
