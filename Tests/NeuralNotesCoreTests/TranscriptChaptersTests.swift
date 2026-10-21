import XCTest
@testable import NeuralNotesCore

final class TranscriptChaptersTests: XCTestCase {
    func testChaptersPreserveEveryCorrectedPhraseAndMergeCoincidentBookmarkHeadings() {
        var session = AudioSession(title: "Lezione")
        session.transcriptionComplete = false
        session.transcript = [TranscriptSegment(start: 10, duration: 1, text: "Inizio"),
            TranscriptSegment(start: 45, duration: 1, text: "Punto segnato"),
            TranscriptSegment(start: 60, duration: 1, text: "Da correggere"),
            TranscriptSegment(start: 299, duration: 1, text: "Fine blocco"),
            TranscriptSegment(start: 301, duration: 1, text: "Secondo blocco"),
            TranscriptSegment(start: 650, duration: 1, text: "Conclusione")]
        session.transcriptCorrections = [TranscriptCorrection(start: 60, text: "Correzione conservata")]
        session.bookmarks = [AudioBookmark(title: "Definizione", seconds: 45), AudioBookmark(title: "Esempi", seconds: 300), AudioBookmark(title: "Esercizi", seconds: 300)]
        let chapters = TranscriptChapters.make(session: session)
        XCTAssertEqual(chapters.map(\.start), [0, 45, 300, 600])
        XCTAssertEqual(chapters[1].title, "Definizione"); XCTAssertEqual(chapters[2].title, "Esempi · Esercizi")
        XCTAssertEqual(chapters[1].minutes.first?.start, 45)
        let actual = chapters.flatMap(\.minutes).map(\.text).joined(separator: " ")
        XCTAssertEqual(actual, "Inizio Punto segnato Correzione conservata Fine blocco Secondo blocco Conclusione")
        XCTAssertFalse(actual.contains("Da correggere"))
        let markdown = TranscriptChapters.markdown(session: session)
        XCTAssertTrue(markdown.contains("Trascrizione parziale")); XCTAssertTrue(markdown.contains("[00:05:00] Esempi · Esercizi"))
        XCTAssertTrue(markdown.contains("[00:00:45] Punto segnato"))
    }
    func testThreeHourLectureExportsAllPhrasesOnceWithStableOrder() {
        var session = AudioSession(title: "Tre ore")
        session.transcript = (0..<1080).map { TranscriptSegment(start: Double($0 * 10), duration: 9, text: "frase_\($0)") }
        let chapters = TranscriptChapters.make(session: session)
        XCTAssertEqual(chapters.count, 36)
        let words = chapters.flatMap(\.minutes).flatMap { $0.text.split(separator: " ").map(String.init) }
        XCTAssertEqual(words, (0..<1080).map { "frase_\($0)" })
        XCTAssertTrue(TranscriptChapters.markdown(session: session).contains("[02:55:00]"))
        XCTAssertEqual(session.transcript.count, 1080)
    }
    func testInvalidTimestampsCannotCreateUnboundedChapterRanges() {
        var session = AudioSession(title: "Controllo")
        session.transcript = [TranscriptSegment(start: .infinity, duration: 1, text: "Non valido"), TranscriptSegment(start: -1, duration: 1, text: "Negativo"), TranscriptSegment(start: 5, duration: .nan, text: "Testo reale")]
        session.bookmarks = [AudioBookmark(title: "Futuro", seconds: 1e100)]
        let chapters = TranscriptChapters.make(session: session)
        XCTAssertEqual(chapters.count, 1); XCTAssertEqual(chapters.first?.minutes.first?.text, "Testo reale")
    }
}
