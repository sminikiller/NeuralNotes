import XCTest
@testable import NeuralNotesCore

final class LectureNotesTests: XCTestCase {
    private let document = UUID()
    /// Twelve minutes of phrases every twenty seconds, with a bookmark at 2:00.
    private func lecture() -> AudioSession {
        var session = AudioSession(title: "Termodinamica"); session.state = "finished"
        session.transcript = stride(from: 0.0, to: 720, by: 20).map { TranscriptSegment(start: $0, duration: 8, text: "frase a \(Int($0)) secondi") }
        session.bookmarks = [AudioBookmark(title: "Secondo principio", seconds: 120)]
        return session
    }

    func testBlocksFollowChaptersAndCoverTheWholeLecture() {
        let blocks = LectureNotesPlanner.plan(lecture())
        XCTAssertEqual(blocks.map(\.start), [0, 120, 300, 600])
        XCTAssertEqual(blocks.map(\.end), [120, 300, 600, 708])
        XCTAssertEqual(blocks[1].title, "Secondo principio"); XCTAssertTrue(blocks[0].title.hasPrefix("Capitolo · "))
        XCTAssertTrue(blocks.allSatisfy { $0.text == nil })
    }

    func testRequestsCarryTimestampedPhrasesOfOneBlockOnly() throws {
        let session = lecture(), blocks = LectureNotesPlanner.plan(session)
        let request = try XCTUnwrap(LectureNotesPlanner.request(for: blocks[1], session: session, documentID: document))
        XCTAssertEqual(request.task, .outline); XCTAssertTrue(request.question.contains("Secondo principio"))
        XCTAssertEqual(request.sources.count, 9)
        XCTAssertEqual(request.sources.first?.text, "[00:02:00] frase a 120 secondi")
        XCTAssertEqual(request.sources.first?.reference, SourceReference(documentID: document, audioSessionID: session.id, seconds: 120))
        XCTAssertFalse(request.sources.contains { $0.text.contains("frase a 300 secondi") })
        XCTAssertFalse(try XCTUnwrap(LectureNotesPlanner.request(for: blocks[0], session: session, documentID: document)).question.contains("Titolo scelto"))
        // A long chapter is grouped to at most forty sources, keeping every phrase.
        var dense = AudioSession(title: "Densa")
        dense.transcript = stride(from: 0.0, to: 300, by: 2).map { TranscriptSegment(start: $0, duration: 2, text: "p\(Int($0))") }
        let block = try XCTUnwrap(LectureNotesPlanner.plan(dense).first)
        let grouped = try XCTUnwrap(LectureNotesPlanner.request(for: block, session: dense, documentID: document))
        XCTAssertLessThanOrEqual(grouped.sources.count, 40)
        XCTAssertEqual(grouped.sources.map(\.text).joined(separator: " ").components(separatedBy: "] p").count - 1, 150)
        XCTAssertNil(LectureNotesPlanner.request(for: LectureNotesBlock(start: 5000, end: 5100, title: "Vuoto"), session: dense, documentID: document))
    }

    func testCitationsBecomeTimesAndMarkdownStatesWhatIsMissing() {
        let references = [SourceReference(documentID: document, audioSessionID: UUID(), seconds: 65), SourceReference(documentID: document, audioSessionID: UUID(), seconds: 3725)]
        let artifact = AIArtifact(text: "## Calore\n- Si trasferisce [1]\n- Entropia [2] [3]", references: references, provider: "Test / modello")
        XCTAssertEqual(LectureNotesPlanner.notesText(from: artifact), "## Calore\n- Si trasferisce [00:01:05]\n- Entropia [01:02:05]")
        var notes = LectureNotes(fingerprint: String(repeating: "a", count: 64), blocks: LectureNotesPlanner.plan(lecture()))
        notes.blocks[0].text = "Appunti puliti"; notes.blocks[0].provider = "Test / modello"; notes.blocks[1].text = ""
        let markdown = LectureNotesPlanner.markdown(title: "Termo\ndinamica", notes: notes)
        XCTAssertTrue(markdown.hasPrefix("# Sbobina · Termo dinamica")); XCTAssertTrue(markdown.contains("Sbobina parziale: 2 blocchi su 4 · Test / modello"))
        XCTAssertTrue(markdown.contains("## [00:02:00] Secondo principio")); XCTAssertTrue(markdown.contains("_Nessun testo riconosciuto"))
        XCTAssertTrue(markdown.contains("_Capitolo non ancora elaborato._")); XCTAssertTrue(notes.isValid); XCTAssertFalse(notes.isComplete)
    }

    func testResumeKeepsNotesUntilTheTranscriptChanges() {
        var session = lecture()
        var notes = LectureNotesPlanner.resume(session)
        XCTAssertEqual(notes.fingerprint.count, 64); notes.blocks[0].text = "Fatto"
        session.lectureNotes = notes
        XCTAssertEqual(LectureNotesPlanner.resume(session).blocks[0].text, "Fatto")
        session.transcript[0].text = "frase corretta"
        let fresh = LectureNotesPlanner.resume(session)
        XCTAssertNotEqual(fresh.fingerprint, notes.fingerprint); XCTAssertNil(fresh.blocks[0].text)
        var renamed = lecture(); renamed.lectureNotes = notes; renamed.bookmarks?[0].title = "Altro titolo"
        XCTAssertNil(LectureNotesPlanner.resume(renamed).blocks[0].text)
    }

    func testPagesSplitOnParagraphsAndNeverLoseText() {
        let paragraphs = (1...30).map { "Paragrafo \($0) " + String(repeating: "x", count: 150) }
        let pages = LectureNotesPlanner.pages(paragraphs.joined(separator: "\n\n"), limit: 1000)
        XCTAssertGreaterThan(pages.count, 1); XCTAssertTrue(pages.allSatisfy { $0.count <= 1000 })
        XCTAssertEqual(pages.joined(separator: "\n\n"), paragraphs.joined(separator: "\n\n"))
        let long = String(repeating: "y", count: 2500)
        XCTAssertEqual(LectureNotesPlanner.pages(long, limit: 1000).map(\.count), [1000, 1000, 500])
    }
}
