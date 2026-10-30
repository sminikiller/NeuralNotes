import XCTest
@testable import NeuralNotesCore

final class MarkerPreferencesTests: XCTestCase {
    func testLegacyWritingOptionsDecodeWithoutMarkerFieldsAndNewWidthsRoundTrip() throws {
        let data = Data(#"{"pen":"pen","eraser":"partial","eraserWidth":18,"markerOnly":false,"returnToPen":false,"presets":[]}"#.utf8)
        var options = try JSONDecoder().decode(WritingOptions.self, from: data)
        XCTAssertNil(options.markerWidth); XCTAssertNil(options.markerSnapWords); XCTAssertNil(options.markerRecentWidths)
        options.markerWidth = 1; options.markerSnapWords = true; options.markerRecentWidths = [1, 3, 8]
        XCTAssertTrue(options.isValid)
        XCTAssertEqual(try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options)), options)
    }
    func testMarkerWidthRejectsNonFiniteOversizedOrExcessiveRecentValues() {
        var options = WritingOptions()
        for width in [Double.nan, .infinity, -1, 0.5, 81] { options.markerWidth = width; XCTAssertFalse(options.isValid) }
        options.markerWidth = 80; XCTAssertTrue(options.isValid)
        options.markerRecentWidths = [1, 2, 3, 4]; XCTAssertFalse(options.isValid)
        options.markerRecentWidths = [1, .nan]; XCTAssertFalse(options.isValid)
    }
}
