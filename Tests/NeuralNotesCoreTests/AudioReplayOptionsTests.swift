import XCTest
@testable import NeuralNotesCore

final class AudioReplayOptionsTests: XCTestCase {
    func testKeyPointsUseBookmarksAndLongTranscriptGapsWithoutDuplicatingOrInventingTimes() {
        var session = AudioSession(title: "Lezione")
        var media = AudioTimelineSegment(file: "audio/test.caf", start: 0, hostStart: 0); media.duration = 180; session.segments = [media]
        session.bookmarks = [.init(title: "Inizio", seconds: 0), .init(title: "Concetto", seconds: 60), .init(title: "Duplicato", seconds: 60.05), .init(title: "Non valido", seconds: .nan)]
        session.transcript = [.init(start: 90, duration: 10, text: "Ripresa"), .init(start: 0, duration: 20, text: "Prima"), .init(start: 18, duration: 42, text: "Si sovrappone")]
        XCTAssertEqual(AudioReplay.keyPoints(session), [0, 60, 90])
        XCTAssertEqual(AudioReplay.keyPoint(1, from: 60, session: session), 90)
        XCTAssertEqual(AudioReplay.keyPoint(-1, from: 90, session: session), 60)
        XCTAssertNil(AudioReplay.keyPoint(1, from: 100, session: session))
        XCTAssertNil(AudioReplay.keyPoint(-1, from: 0, session: session))
    }
    func testShowAllCurrentStrokeIsOnlyTheRecentLinkedStrokeAndUnknownModeFallsBack() throws {
        let session = UUID()
        let anchors = [StrokeAnchor(signature: "old", audioSessionID: session, seconds: 1), StrokeAnchor(signature: "now", audioSessionID: session, seconds: 12)]
        XCTAssertEqual(AudioReplay.current(signatures: ["old", "unlinked", "now"], anchors: anchors, sessionID: session, seconds: 12.5), [2])
        XCTAssertTrue(AudioReplay.current(signatures: ["now"], anchors: anchors, sessionID: session, seconds: 18).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(AudioReplayMode.self, from: Data("\"future\"".utf8)), .follow)
    }
}
