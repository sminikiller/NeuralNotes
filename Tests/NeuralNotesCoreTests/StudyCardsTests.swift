import XCTest
@testable import NeuralNotesCore

final class StudyCardsTests: XCTestCase {
    func testGeneratedCardAnswerOccursInTheReferencedSource() {
        let source = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 3)
        let text = "La fotosintesi converte energia luminosa in energia chimica nelle cellule vegetali."
        let cards = StudyCardBuilder.make(from: [IndexedChunk(text: text, reference: source), IndexedChunk(text: text, reference: source)])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].source, source)
        XCTAssertTrue(text.contains(cards[0].answer))
        XCTAssertEqual(cards[0].question.replacingOccurrences(of: "[ … ]", with: cards[0].answer), String(text.dropLast()))
    }

    func testReviewScheduleAndFailureAreDeterministic() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var card = StudyCard(question: "Domanda", answer: "Risposta", source: SourceReference(documentID: UUID()), now: now)
        card.review(.good, now: now)
        XCTAssertEqual(card.intervalDays, 1); XCTAssertEqual(card.dueAt, now.addingTimeInterval(86400))
        card.review(.easy, now: now)
        XCTAssertEqual(card.intervalDays, 3)
        card.review(.again, now: now)
        XCTAssertEqual(card.intervalDays, 0); XCTAssertEqual(card.reviewCount, 3)
        XCTAssertEqual(card.dueAt, now.addingTimeInterval(600))
    }

    func testProgressSurvivesWorkspaceRestartWithoutDuplicatingCards() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let card = StudyCard(question: "Domanda", answer: "Risposta", source: SourceReference(documentID: manifest.documentID))
        try await workspace.addStudyCards([card, card]); try await workspace.reviewCard(card.id, rating: .good)
        let reopened = DocumentWorkspace(package: workspace.package, documentID: manifest.documentID, notebookID: manifest.notebookID)
        let cards = try await reopened.catalog().studyCards
        XCTAssertEqual(cards?.count, 1); XCTAssertEqual(cards?.first?.reviewCount, 1)
        XCTAssertEqual(cards?.first?.intervalDays, 1)
    }
}
