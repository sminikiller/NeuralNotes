import XCTest
@testable import NeuralNotesCore

final class StudyStatisticsTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDailyCountsStreakAndForecastUseCalendarAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        let now = date("2026-10-25T12:00:00Z")
        let dates = [date("2026-10-23T12:00:00Z"), date("2026-10-24T12:00:00Z"), now]
        let events = dates.map { StudyReviewEvent(cardID: UUID(), rating: .good, date: $0, intervalDays: 1) }
        var overdue = StudyCard(question: "A", answer: "B", source: SourceReference(documentID: UUID()), now: dates[0])
        overdue.intervalDays = 21; overdue.reviewCount = 2
        let tomorrow = StudyCard(question: "C", answer: "D", source: overdue.source, now: date("2026-10-26T08:00:00Z"))
        let later = StudyCard(question: "E", answer: "F", source: overdue.source, now: date("2026-11-05T08:00:00Z"))
        let stats = StudyStatistics.make(cards: [overdue, tomorrow, later], events: events, now: now, calendar: calendar)
        XCTAssertEqual(stats.streakDays, 3); XCTAssertEqual(stats.recordedReviews, 3); XCTAssertEqual(stats.recalledReviews, 3)
        XCTAssertEqual(stats.dueNow, 1); XCTAssertEqual(stats.matureCards, 1)
        XCTAssertEqual(stats.recentDays.map(\.count), [0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(stats.forecast.map(\.count), [1, 1, 0, 0, 0, 0, 0])
        XCTAssertEqual(stats.forecast[1].date.timeIntervalSince(stats.forecast[0].date), 25 * 3600)
    }
    func testNoInventedHistoryAndStreakCanContinueFromYesterday() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = date("2026-10-21T10:00:00Z"), yesterday = date("2026-10-20T10:00:00Z")
        var old = StudyCard(question: "A", answer: "B", source: SourceReference(documentID: UUID()), now: now); old.reviewCount = 42
        XCTAssertEqual(StudyStatistics.make(cards: [old], events: [], now: now).recordedReviews, 0)
        let events = [StudyReviewEvent(cardID: old.id, rating: .again, date: yesterday, intervalDays: 0),
            StudyReviewEvent(cardID: old.id, rating: .easy, date: now.addingTimeInterval(86400), intervalDays: 3)]
        let stats = StudyStatistics.make(cards: [old], events: events, now: now, calendar: calendar)
        XCTAssertEqual(stats.streakDays, 1); XCTAssertEqual(stats.recordedReviews, 1); XCTAssertEqual(stats.recalledReviews, 0)
    }
    func testReviewAndLogCommitTogetherAndSurviveCloneMergeAndCardRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), document = UUID(), book = UUID()
        try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        let page = try await workspace.addPage(), now = date("2026-10-21T10:00:00Z")
        let card = StudyCard(question: "Q", answer: "A", source: SourceReference(documentID: document, pageID: page.id), now: now)
        try await workspace.addStudyCards([card]); try await workspace.reviewCard(card.id, rating: .good, now: now)
        var stored = try await workspace.catalog()
        XCTAssertEqual(stored.studyCards?.first?.reviewCount, 1); XCTAssertEqual(stored.reviewLog?.first?.cardID, card.id)
        do { try await workspace.reviewCard(UUID(), rating: .good, now: now); XCTFail("Reviewed missing card") } catch LibraryFailure.missingItem { }
        let copyID = UUID(), copyBook = UUID(); try await workspace.clone(to: store, documentID: copyID, notebookID: copyBook)
        let copy = DocumentWorkspace(package: store.packageURL(for: copyID), documentID: copyID, notebookID: copyBook)
        let copied = try await copy.catalog()
        XCTAssertEqual(copied.reviewLog?.first?.cardID, copied.studyCards?.first?.id)
        XCTAssertNotEqual(copied.reviewLog?.first?.id, stored.reviewLog?.first?.id)
        _ = try await workspace.appendNative(from: copy.package)
        try await workspace.removeStudyCard(card.id); stored = try await workspace.catalog()
        XCTAssertEqual(stored.reviewLog?.count, 2); XCTAssertEqual(stored.studyCards?.count, 1)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
}
