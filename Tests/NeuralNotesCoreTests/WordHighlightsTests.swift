import XCTest
import Foundation
@testable import NeuralNotesCore

final class WordHighlightsTests: XCTestCase {
    private var words: [PageWord] {
        [PageWord(text: "Energia", rect: CGRect(x: 20, y: 50, width: 60, height: 16)),
         PageWord(text: "conservata", rect: CGRect(x: 86, y: 50, width: 80, height: 16)),
         PageWord(text: "Seconda", rect: CGRect(x: 20, y: 75, width: 60, height: 16))]
    }
    func testLensAndMarkerShareSourcePriorityAndExactUnderlineSelection() throws {
        let trace = [CGPoint(x: 24, y: 68), CGPoint(x: 100, y: 68), CGPoint(x: 150, y: 68)]
        let other = [PageWord(text: "Altro riquadro", rect: words[0].rect)]
        let selected = try XCTUnwrap(PageWords.selection(trace: trace, groups: [[], words, other]))
        XCTAssertEqual(selected.words, words); XCTAssertEqual(selected.indices, [0, 1])
        XCTAssertEqual(selected.indices, PageWords.pick(trace: trace, in: words, area: false))
        let reversed = try XCTUnwrap(PageWords.selection(trace: Array(trace.reversed()), groups: [words]))
        XCTAssertEqual(reversed.indices, selected.indices)
        XCTAssertNil(PageWords.selection(trace: [CGPoint(x: 500, y: 500)], groups: [words]))
        let marks = try WordHighlights.appending(words: selected.words, indices: selected.indices, to: [], color: .yellow, width: 600, height: 800)
        XCTAssertEqual(marks.map(\.text), ["Energia", "conservata"])
        XCTAssertTrue(marks.allSatisfy { $0.wordHighlight == true && $0.opacity == 0.25 && $0.color == .yellow })
        XCTAssertLessThan(marks.last!.y + marks.last!.height, Double(words[2].rect.minY))
    }
    func testRepeatPassDoesNotAddMarksOrDarkenButAChosenDifferentColorDoes() throws {
        let first = try WordHighlights.appending(words: words, indices: [0, 1, 1, -1, 99], to: [], color: .green, width: 600, height: 800)
        XCTAssertEqual(first.count, 2)
        let repeated = try WordHighlights.appending(words: words, indices: [1, 0], to: first, color: .green, width: 600, height: 800)
        XCTAssertEqual(repeated, first)
        let recolored = try WordHighlights.appending(words: words, indices: [0], to: first, color: .orange, width: 600, height: 800)
        XCTAssertEqual(recolored.count, 3); XCTAssertEqual(recolored.last?.color, .orange)
        XCTAssertEqual(Set(recolored.map(\.id)).count, 3)
    }
    func testClipsToPageSkipsInvalidWordsAndEnforcesMetadataLimit() throws {
        let source = [PageWord(text: "Bordo", rect: CGRect(x: -2, y: -1, width: 20, height: 12)),
                      PageWord(text: "Fuori", rect: CGRect(x: 700, y: 0, width: 20, height: 12)),
                      PageWord(text: "Non finito", rect: CGRect(x: Double.nan, y: 0, width: 20, height: 12))]
        let marks = try WordHighlights.appending(words: source, indices: [0, 1, 2], to: [], color: .yellow, width: 600, height: 800)
        XCTAssertEqual(marks.count, 1); XCTAssertEqual(marks[0].x, 0); XCTAssertEqual(marks[0].y, 0)
        XCTAssertTrue(try WordHighlights.appending(words: words, indices: [0], to: [], color: InkColor(-1, 0, 0), width: 600, height: 800).isEmpty)
        let full = (0..<20_000).map { _ in PDFMarkup(kind: .highlight, x: 300, y: 400, width: 10, height: 10, text: "Preesistente") }
        XCTAssertThrowsError(try WordHighlights.appending(words: words, indices: [0], to: full, color: .yellow, width: 600, height: 800))
    }
    func testLegacyMarkupAndNewMetadataRoundTripAndValidation() throws {
        let legacy = PDFMarkup(kind: .underline, x: 1, y: 2, width: 3, height: 4, text: "Vecchio PDF")
        let decoded = try JSONDecoder().decode(PDFMarkup.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded, legacy); XCTAssertNil(decoded.wordHighlight); XCTAssertNil(decoded.color); XCTAssertNil(decoded.opacity)
        var page = PageSnapshot()
        page.pdfMarkups = try WordHighlights.appending(words: words, indices: [0], to: [legacy], color: .blue, width: page.width, height: page.height)
        try PageValidation.validate(page)
        XCTAssertEqual(try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(page)), page)
        var invalid = page; invalid.pdfMarkups?[1].opacity = 1.1; XCTAssertThrowsError(try PageValidation.validate(invalid))
        invalid = page; invalid.pdfMarkups?[1].color = InkColor(0, -1, 0); XCTAssertThrowsError(try PageValidation.validate(invalid))
        invalid = page; invalid.pdfMarkups?[1].kind = .underline; XCTAssertThrowsError(try PageValidation.validate(invalid))
        invalid = page; invalid.pdfMarkups?.append(page.pdfMarkups![1]); XCTAssertThrowsError(try PageValidation.validate(invalid))
        XCTAssertEqual(try JSONDecoder().decode(PDFMarkupKind.self, from: Data("\"future-mark\"".utf8)), .highlight)
    }
    func testEraserObjectOptOutIsOptionalAndSurvivesWorkspaceRoundTrip() throws {
        var options = WritingOptions(); XCTAssertTrue(options.erasesObjects)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        json.removeValue(forKey: "eraseObjects")
        let old = try JSONDecoder().decode(WritingOptions.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.eraseObjects); XCTAssertTrue(old.erasesObjects)
        options.eraseObjects = false
        let decoded = try JSONDecoder().decode(WritingOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options); XCTAssertFalse(decoded.erasesObjects)
        options.eraserTarget = .marker; options.eraseObjects = true; XCTAssertFalse(options.erasesObjects)
    }
}
