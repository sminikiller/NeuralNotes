import XCTest
@testable import NeuralNotesCore

final class SourceContextTests: XCTestCase {
    func testOverviewIncludesTheEndOfALongLectureAndKeepsTimestamps() {
        let document = UUID(), session = UUID()
        let chunks = (0..<180).map { IndexedChunk(text: "Minuto \($0)", reference: SourceReference(documentID: document, audioSessionID: session, seconds: Double($0 * 60)), kind: .audio) }
        let selection = SourceContext.select(chunks, spread: true)
        XCTAssertEqual(selection.sources.count, 40); XCTAssertTrue(selection.wasTruncated); XCTAssertEqual(selection.availableCount, 180)
        XCTAssertEqual(selection.sources.first?.reference.seconds, 0); XCTAssertEqual(selection.sources.last?.reference.seconds, 179 * 60)
        XCTAssertEqual(Set(selection.sources.compactMap { $0.reference.seconds }).count, 40)
        XCTAssertEqual(selection.sources.last?.text, chunks.last?.text)
    }
    func testRankedSourcesKeepOrderAndBudgetPreservesUnicode() {
        let reference = SourceReference(documentID: UUID())
        let chunks = (0..<40).map { IndexedChunk(text: String(repeating: "👨‍👩‍👧‍👦\($0) ", count: 4000), reference: reference) }
        let selection = SourceContext.select(chunks)
        XCTAssertEqual(selection.sources.count, 40); XCTAssertTrue(selection.wasTruncated)
        let units = selection.sources.reduce(0) { $0 + $1.text.utf16.count }
        XCTAssertLessThanOrEqual(units, 80_000); XCTAssertGreaterThan(units, 79_000)
        XCTAssertTrue(selection.sources.allSatisfy { $0.text.utf16.count <= 8000 && !$0.text.contains("�") })
        XCTAssertTrue(selection.sources[39].text.hasPrefix("👨‍👩‍👧‍👦39 "))
    }
    func testSmallContextIsExactAndInvalidBudgetsAreEmpty() {
        let chunks = [IndexedChunk(text: "Intero testo", reference: SourceReference(documentID: UUID()))]
        let selection = SourceContext.select(chunks, spread: true)
        XCTAssertFalse(selection.wasTruncated); XCTAssertEqual(selection.sources.first?.text, chunks[0].text)
        XCTAssertTrue(SourceContext.select(chunks, maximumSources: -1).sources.isEmpty)
        XCTAssertTrue(SourceContext.select(chunks, maximumCharacters: 0).sources.isEmpty)
        XCTAssertTrue(SourceContext.select(chunks, maximumPerSource: 0).sources.isEmpty)
        let emoji = [IndexedChunk(text: "👨‍👩‍👧‍👦", reference: chunks[0].reference)]
        XCTAssertTrue(SourceContext.select(emoji, maximumCharacters: 1).sources.isEmpty)
    }
}
