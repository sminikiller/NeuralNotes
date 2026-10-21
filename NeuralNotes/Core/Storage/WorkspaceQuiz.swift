import Foundation

public extension DocumentWorkspace {
    func startQuiz(_ bank: QuizBank, mode: QuizMode, minutes: Int = 20, now: Date = Date()) throws -> QuizRun {
        var value = try catalog()
        var canonical = bank; canonical.createdAt = Date(timeIntervalSince1970: floor(bank.createdAt.timeIntervalSince1970))
        let run = QuizRun(bank: canonical, mode: mode, minutes: minutes, now: now)
        guard run.isValid else { throw LibraryFailure.corruptDocument }
        guard value.activeQuiz == nil else { throw WorkspaceFailure.staleRevision }
        value.activeQuiz = run; try write(value, "catalog.json"); return run
    }
    func saveQuiz(_ run: QuizRun) throws {
        guard run.isValid else { throw LibraryFailure.corruptDocument }
        var value = try catalog()
        guard let current = value.activeQuiz, current.id == run.id, current.revision < run.revision, current.bank == run.bank,
              current.mode == run.mode, current.startedAt == run.startedAt, current.deadline == run.deadline else { throw WorkspaceFailure.staleRevision }
        if run.submittedAt != nil {
            value.activeQuiz = nil; value.quizHistory = Array(((value.quizHistory ?? []) + [run]).suffix(10))
        } else { value.activeQuiz = run }
        try write(value, "catalog.json")
    }
    func archiveActiveQuiz() throws {
        var value = try catalog(); guard let run = value.activeQuiz else { return }
        value.quizHistory = Array(((value.quizHistory ?? []) + [run]).suffix(10)); value.activeQuiz = nil
        try write(value, "catalog.json")
    }
    func resumeQuiz(_ id: UUID) throws -> QuizRun {
        var value = try catalog()
        guard value.activeQuiz == nil, let run = value.quizHistory?.first(where: { $0.id == id }), run.submittedAt == nil else { throw WorkspaceFailure.staleRevision }
        value.quizHistory?.removeAll { $0.id == id }; value.activeQuiz = run; try write(value, "catalog.json"); return run
    }
}
