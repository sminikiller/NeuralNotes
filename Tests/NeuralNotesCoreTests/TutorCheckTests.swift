import XCTest
@testable import NeuralNotesCore

final class TutorCheckTests: XCTestCase {
    private let page = UUID(), other = UUID(), document = UUID()

    func testRequestUsesTheExpectedAnswerAndOnlyTheCardSourcePage() throws {
        let source = SourceReference(documentID: document, pageID: page, pageRevision: 1)
        let card = StudyCard(question: "Che cos’è l’entropia?", answer: "Una misura del disordine", source: source)
        let context = [IndexedChunk(text: "Pagina della carta", reference: source),
                       IndexedChunk(text: "Altra pagina", reference: SourceReference(documentID: document, pageID: other))]
        let request = try XCTUnwrap(TutorCheck.request(card: card, answer: "  il disordine  ", context: context))
        XCTAssertEqual(request.task, .chat)
        XCTAssertEqual(request.sources.map(\.text), ["Risposta attesa della flashcard: Una misura del disordine", "Pagina della carta"])
        XCTAssertTrue(request.question.contains("«il disordine»")); XCTAssertLessThanOrEqual(request.question.count, 4000)
        XCTAssertNil(TutorCheck.request(card: card, answer: " \n ", context: context))
        XCTAssertNil(TutorCheck.request(card: card, answer: String(repeating: "x", count: 1501), context: context))
        let long = StudyCard(question: String(repeating: "q", count: 5000), answer: "a", source: source)
        XCTAssertLessThanOrEqual(try XCTUnwrap(TutorCheck.request(card: long, answer: String(repeating: "b", count: 1500), context: [])).question.count, 4000)
    }

    func testAudioCardsUseTheirRecordingAndManualCardsOnlyTheExpectedAnswer() throws {
        let session = UUID()
        let audio = StudyCard(question: "Q", answer: "A", source: SourceReference(documentID: document, audioSessionID: session, seconds: 30))
        let context = [IndexedChunk(text: "Lezione", reference: SourceReference(documentID: document, audioSessionID: session, seconds: 25)),
                       IndexedChunk(text: "Pagina", reference: SourceReference(documentID: document, pageID: page))]
        XCTAssertEqual(try XCTUnwrap(TutorCheck.request(card: audio, answer: "x", context: context)).sources.count, 2)
        let manual = StudyCard(question: "Q", answer: "A", source: SourceReference(documentID: document))
        XCTAssertEqual(try XCTUnwrap(TutorCheck.request(card: manual, answer: "x", context: context)).sources.count, 1)
    }

    func testVerdictAndSuggestedRating() {
        XCTAssertEqual(TutorCheck.verdict("Corretta: hai indicato [1]"), .correct)
        XCTAssertEqual(TutorCheck.verdict("**Parziale.** Manca"), .partial)
        XCTAssertEqual(TutorCheck.verdict("Da rivedere — la risposta"), .wrong)
        XCTAssertNil(TutorCheck.verdict("La risposta è buona"))
        XCTAssertEqual(TutorCheck.suggestedRating(.correct), .good); XCTAssertEqual(TutorCheck.suggestedRating(.partial), .hard)
        XCTAssertEqual(TutorCheck.suggestedRating(.wrong), .again)
    }

    func testHardRatingSchedulesBetweenAgainAndGood() throws {
        let now = Date(timeIntervalSince1970: 1_000_000), source = SourceReference(documentID: document)
        var hard = StudyCard(question: "Q", answer: "A", source: source, now: now), good = hard
        hard.intervalDays = 10; hard.reviewCount = 3; good.intervalDays = 10; good.reviewCount = 3
        hard.review(.hard, now: now); good.review(.good, now: now)
        XCTAssertEqual(hard.intervalDays, 12); XCTAssertLessThan(hard.dueAt, good.dueAt)
        var adaptiveHard = StudyCard(question: "Q", answer: "A", source: source, now: now), adaptiveGood = adaptiveHard
        try adaptiveHard.reviewAdaptive(.hard, now: now); try adaptiveGood.reviewAdaptive(.good, now: now)
        XCTAssertLessThanOrEqual(adaptiveHard.dueAt, adaptiveGood.dueAt); XCTAssertEqual(adaptiveHard.memory?.reps, 1)
    }
}
