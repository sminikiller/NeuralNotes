import XCTest
import NeuralNotesCore

final class TranscriptPhrasesTests: XCTestCase {
    func testWordsBecomeShortPhrasesKeepingTextAndFirstStart() {
        let words = (0..<20).map { TranscriptSegment(start: 10 + Double($0) * 0.4, duration: 0.3, text: "w\($0)") }
        let phrases = TranscriptText.phrases(words)
        XCTAssertEqual(phrases.first?.start, 10)
        XCTAssertEqual(phrases.map(\.text).joined(separator: " "), words.map(\.text).joined(separator: " "))
        XCTAssertLessThan(phrases.count, words.count)
        XCTAssertTrue(phrases.allSatisfy { $0.duration <= 10 })
    }

    func testPhraseNeverCrossesAMinuteAndEndsAfterPauseOrSentence() {
        let words = [TranscriptSegment(start: 58, duration: 0.5, text: "fine"), TranscriptSegment(start: 59, duration: 0.5, text: "minuto"),
                     TranscriptSegment(start: 60.2, duration: 0.5, text: "nuovo"), TranscriptSegment(start: 61, duration: 0.5, text: "frase."),
                     TranscriptSegment(start: 61.6, duration: 0.5, text: "Altra"), TranscriptSegment(start: 66, duration: 0.5, text: "dopo pausa")]
        let phrases = TranscriptText.phrases(words)
        XCTAssertEqual(phrases.map(\.text), ["fine minuto", "nuovo frase.", "Altra", "dopo pausa"])
        XCTAssertEqual(TranscriptText.minutes(phrases).map(\.start), [0, 60])
    }

    func testEmptyAndInvalidWordsAreDropped() {
        let words = [TranscriptSegment(start: 1, duration: 0.2, text: "  "), TranscriptSegment(start: .nan, duration: 1, text: "x"),
                     TranscriptSegment(start: 2, duration: 0.3, text: "ok")]
        XCTAssertEqual(TranscriptText.phrases(words).map(\.text), ["ok"])
    }

    func testTwoHourWindowsCoverEveryFrameWithoutGapsOrOverlaps() {
        let rate = 44_100.0, length = Int64(7_200 * rate)
        let ranges = SpeechWindow.plan(duration: 7_200, maximum: 45).compactMap { $0.frames(sampleRate: rate, length: length) }
        XCTAssertEqual(ranges.count, 160)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, length)
        for (a, b) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        XCTAssertNil(SpeechWindow(start: 7_300, duration: 45).frames(sampleRate: rate, length: length))
        XCTAssertNil(SpeechWindow(start: 0, duration: 45).frames(sampleRate: 0, length: length))
    }

    func testFirstMinutePreviewUsesOnlyTheEarliestMinute() {
        let segments = [TranscriptSegment(start: 130, duration: 1, text: "terzo"), TranscriptSegment(start: 75, duration: 1, text: "dopo"),
                        TranscriptSegment(start: 62, duration: 1, text: "primo"), TranscriptSegment(start: 64, duration: 1, text: "minuto")]
        XCTAssertEqual(TranscriptText.firstMinuteText(segments), "primo minuto dopo")
        XCTAssertEqual(TranscriptText.firstMinuteText([]), "")
    }
}
