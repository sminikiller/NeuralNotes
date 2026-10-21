import XCTest
@testable import NeuralNotesCore

final class QuizTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000.75)
    private var reference: SourceReference { SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 1) }
    private func bank(reference: SourceReference) -> QuizBank {
        QuizBank(title: "Controllo", questions: [QuizQuestion(prompt: "Domanda [1]", options: ["Uno", "Due", "Tre", "Quattro"], correctIndex: 1,
            explanation: "La fonte indica Due [1]", references: [reference])], provider: "fixture", now: now)
    }
    private func fixture() throws -> (URL, NativeDocumentStore, DocumentWorkspace, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), id = UUID(), book = UUID()
        let store = try NativeDocumentStore(root: root); try store.create(DocumentManifest(documentID: id, notebookID: book))
        return (root, store, DocumentWorkspace(package: store.packageURL(for: id), documentID: id, notebookID: book), book)
    }
    func testStructuredQuizRejectsInventedReferencesOutOfRangeAnswersAndDuplicatedOptions() throws {
        let reference = reference, request = QuizRequest(sources: [IndexedChunk(text: "Fonte", reference: reference)], count: 3)
        var value = bank(reference: reference); XCTAssertNoThrow(try value.validated(for: request))
        value.questions[0].correctIndex = 4; XCTAssertThrowsError(try value.validated(for: request))
        value = bank(reference: reference); value.questions[0].options[1] = " UNO "; XCTAssertThrowsError(try value.validated(for: request))
        value = bank(reference: self.reference); XCTAssertThrowsError(try value.validated(for: request))
        value = bank(reference: reference); value.questions[0].explanation = "Altra fonte [2]"; XCTAssertThrowsError(try value.validated(for: request))
    }
    func testExamDeadlineCannotBeExtendedByReopeningAndUnansweredQuestionsScoreZero() throws {
        let value = bank(reference: reference); var exam = QuizRun(bank: value, mode: .exam, minutes: 1, now: now)
        XCTAssertTrue(exam.isValid); XCTAssertEqual(exam.score, 0)
        let deadline = try XCTUnwrap(exam.deadline)
        XCTAssertThrowsError(try exam.choose(1, question: 0, now: deadline))
        try exam.submit(now: deadline.addingTimeInterval(10)); XCTAssertEqual(exam.score, 0)
        XCTAssertThrowsError(try exam.choose(1, question: 0, now: now))
        XCTAssertThrowsError(try exam.submit(now: now))
    }
    func testStudyLocksAnswerAfterFeedbackAndExamAllowsChangesBeforeSubmission() throws {
        let bank = bank(reference: reference)
        var study = QuizRun(bank: bank, mode: .study, now: now); try study.choose(0, question: 0, now: now)
        XCTAssertThrowsError(try study.choose(1, question: 0, now: now)); XCTAssertEqual(study.score, 0)
        var exam = QuizRun(bank: bank, mode: .exam, now: now); try exam.choose(0, question: 0, now: now); try exam.choose(1, question: 0, now: now)
        try exam.submit(now: now); XCTAssertEqual(exam.score, 1); XCTAssertEqual(exam.answeredCount, 1)
    }
    func testLocalQuizUsesOnlyDistinctSavedAnswersAndIsDeterministicForASeed() throws {
        let source = reference
        let cards = (0..<8).map { StudyCard(question: "Domanda \($0)", answer: "Risposta \($0)", source: source) }
        let first = try XCTUnwrap(QuizBuilder.make(cards: cards, limit: 6, seed: 123, now: now))
        let second = try XCTUnwrap(QuizBuilder.make(cards: cards, limit: 6, seed: 123, now: now))
        XCTAssertEqual(first.questions.map(\.options), second.questions.map(\.options))
        XCTAssertTrue(first.isValid); XCTAssertEqual(first.questions.count, 6)
        for question in first.questions {
            XCTAssertEqual(Set(question.options).count, 4)
            XCTAssertTrue(cards.contains { $0.question == question.prompt && $0.answer == question.options[question.correctIndex] })
            XCTAssertEqual(question.references, [source])
        }
        XCTAssertNil(QuizBuilder.make(cards: Array(cards.prefix(3))))
    }
    func testProgressPersistsWithFractionalClockStaleWritesAreRejectedAndHistoryKeepsScore() async throws {
        let (root, _, workspace, book) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage()
        var quiz = try await workspace.startQuiz(bank(reference: SourceReference(documentID: workspace.documentID, pageID: page.id)), mode: .exam, now: now)
        let stale = quiz; try quiz.choose(1, question: 0, now: now); try await workspace.saveQuiz(quiz)
        let reopened = DocumentWorkspace(package: workspace.package, documentID: workspace.documentID, notebookID: book)
        let current = try await reopened.catalog(); XCTAssertEqual(current.activeQuiz, quiz)
        do { try await reopened.saveQuiz(stale); XCTFail("Stale quiz replaced progress") } catch WorkspaceFailure.staleRevision { }
        try quiz.submit(now: now.addingTimeInterval(20)); try await reopened.saveQuiz(quiz)
        let stored = try await reopened.catalog(); XCTAssertNil(stored.activeQuiz); XCTAssertEqual(stored.quizHistory?.last?.score, 1)
        XCTAssertEqual(stored.quizHistory?.last, quiz)
    }
    func testCloneAndMergeRemapQuizSourcesAndKeepIndependentProgress() async throws {
        let (root, store, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = try await workspace.addPage()
        let original = try await workspace.startQuiz(bank(reference: SourceReference(documentID: workspace.documentID, pageID: page.id)), mode: .study, now: now)
        let copiedID = UUID(), book = UUID(); try await workspace.clone(to: store, documentID: copiedID, notebookID: book)
        let copy = DocumentWorkspace(package: store.packageURL(for: copiedID), documentID: copiedID, notebookID: book)
        let pages = try await copy.pages(), catalog = try await copy.catalog()
        XCTAssertNotEqual(catalog.activeQuiz?.id, original.id)
        XCTAssertEqual(catalog.activeQuiz?.bank.questions[0].references[0].documentID, copiedID)
        XCTAssertEqual(catalog.activeQuiz?.bank.questions[0].references[0].pageID, pages[0].id)
        _ = try await workspace.appendNative(from: copy.package)
        let merged = try await workspace.catalog(); XCTAssertEqual(merged.activeQuiz?.id, original.id); XCTAssertEqual(merged.quizHistory?.count, 1)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
    func testMetadataLimitCannotReplaceTheLastReadableCatalog() async throws {
        let (root, _, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let first = StudyCard(question: "Conserva", answer: "Questa risposta", source: reference)
        try await workspace.addStudyCards([first])
        let before = try Data(contentsOf: workspace.package.appendingPathComponent("catalog.json"))
        let large = String(repeating: "x", count: 100_000)
        let cards = (0..<180).map { StudyCard(question: "\($0)", answer: large, source: first.source) }
        do { try await workspace.addStudyCards(cards); XCTFail("Unreadable catalog committed") } catch WorkspaceFailure.oversizedMetadata { }
        let catalog = try await workspace.catalog(); XCTAssertEqual(catalog.studyCards?.map(\.id), [first.id])
        XCTAssertEqual(try Data(contentsOf: workspace.package.appendingPathComponent("catalog.json")), before)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
    func testArchivedPracticeResumesItsExactAnswersBeforeFinalSubmission() async throws {
        let (root, _, workspace, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var run = try await workspace.startQuiz(bank(reference: reference), mode: .study, now: now)
        try run.choose(1, question: 0, now: now); try await workspace.saveQuiz(run); try await workspace.archiveActiveQuiz()
        let archived = try await workspace.catalog(); XCTAssertNil(archived.activeQuiz); XCTAssertEqual(archived.quizHistory?.first, run)
        var resumed = try await workspace.resumeQuiz(run.id); XCTAssertEqual(resumed, run)
        XCTAssertThrowsError(try resumed.choose(0, question: 0, now: now))
        try resumed.submit(now: now); try await workspace.saveQuiz(resumed)
        let complete = try await workspace.catalog(); XCTAssertEqual(complete.quizHistory?.count, 1); XCTAssertEqual(complete.quizHistory?.first?.score, 1)
    }
}
