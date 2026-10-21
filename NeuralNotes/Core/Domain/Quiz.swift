import Foundation

public struct QuizRequest: Codable, Sendable {
    public var sources: [IndexedChunk]
    public var count: Int
    public init(sources: [IndexedChunk], count: Int = 8) { self.sources = sources; self.count = count }
    public var isValid: Bool { (1...12).contains(count) && LookupRequest(term: "Quiz", sources: sources).isValid }
}
public struct QuizQuestion: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var prompt: String
    public var options: [String]
    public var correctIndex: Int
    public var explanation: String
    public var references: [SourceReference]
    public init(prompt: String, options: [String], correctIndex: Int, explanation: String, references: [SourceReference]) {
        self.prompt = prompt; self.options = options; self.correctIndex = correctIndex; self.explanation = explanation; self.references = references
    }
    public var isValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.count <= 1000 && options.count == 4 && (0..<4).contains(correctIndex)
            && options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 }
            && Set(options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping.lowercased() }).count == 4
            && !explanation.isEmpty && explanation.count <= 2000 && (1...40).contains(references.count)
            && references.allSatisfy { ($0.seconds?.isFinite != false) && ($0.seconds ?? 0) >= 0 && ($0.pageRevision ?? 0) >= 0 }
    }
}
public struct QuizBank: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var questions: [QuizQuestion]
    public var provider: String
    public var createdAt: Date
    public init(title: String, questions: [QuizQuestion], provider: String, now: Date = Date()) { self.title = title; self.questions = questions; self.provider = provider; createdAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)) }
    public var isValid: Bool {
        (try? LibraryName.validated(title)) == title && (1...12).contains(questions.count) && questions.allSatisfy(\.isValid)
            && Set(questions.map(\.id)).count == questions.count && !provider.isEmpty && provider.count <= 240
            && createdAt.timeIntervalSince1970.isFinite && createdAt.timeIntervalSince1970 >= 0
    }
    public func validated(for request: QuizRequest) throws -> QuizBank {
        guard request.isValid, isValid, questions.count <= request.count else { throw AIWireFailure.response }
        let allowed = request.sources.map(\.reference), pattern = try NSRegularExpression(pattern: "\\[(\\d+)\\]")
        for question in questions {
            guard question.references.allSatisfy({ allowed.contains($0) }) else { throw AIWireFailure.citation }
            for text in [question.prompt, question.explanation] + question.options {
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range(at: 1), in: text), let value = Int(text[range]), (1...question.references.count).contains(value) else { throw AIWireFailure.citation }
                }
            }
        }
        return self
    }
}
public enum QuizMode: String, Codable, CaseIterable, Sendable { case study, exam }
public struct QuizRun: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var revision = 0
    public var bank: QuizBank
    public var mode: QuizMode
    public var answers: [Int?]
    public var cursor = 0
    public var startedAt: Date
    public var deadline: Date?
    public var submittedAt: Date?
    public init(bank: QuizBank, mode: QuizMode, minutes: Int = 20, now: Date = Date()) {
        self.bank = bank; self.mode = mode; answers = Array(repeating: nil, count: bank.questions.count); startedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        deadline = mode == .exam ? startedAt.addingTimeInterval(Double(min(120, max(1, minutes))) * 60) : nil
    }
    public var score: Int { bank.questions.indices.filter { answers.indices.contains($0) && answers[$0] == bank.questions[$0].correctIndex }.count }
    public var answeredCount: Int { answers.compactMap { $0 }.count }
    public var isValid: Bool {
        bank.isValid && revision >= 0 && revision < Int.max && answers.count == bank.questions.count && answers.allSatisfy { $0 == nil || (0..<4).contains($0!) }
            && bank.questions.indices.contains(cursor) && startedAt.timeIntervalSince1970.isFinite && startedAt.timeIntervalSince1970 >= 0
            && (deadline.map { $0.timeIntervalSince1970.isFinite && $0 > startedAt && $0.timeIntervalSince(startedAt) <= 7200 } ?? true)
            && (submittedAt.map { $0.timeIntervalSince1970.isFinite && $0 >= startedAt } ?? true)
            && ((mode == .exam) == (deadline != nil))
    }
    public func expired(at now: Date = Date()) -> Bool { deadline.map { now >= $0 } ?? false }
    public mutating func choose(_ option: Int, question: Int, now: Date = Date()) throws {
        guard isValid, submittedAt == nil, now.timeIntervalSince1970.isFinite, now >= startedAt, !expired(at: now), (0..<4).contains(option), answers.indices.contains(question),
              mode == .exam || answers[question] == nil else { throw WorkspaceFailure.staleRevision }
        answers[question] = option; revision += 1
    }
    public mutating func submit(now: Date = Date()) throws {
        guard isValid, submittedAt == nil, now >= startedAt, now.timeIntervalSince1970.isFinite else { throw WorkspaceFailure.staleRevision }
        submittedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)); revision += 1
    }
    public func copied(remapping reference: (SourceReference) -> SourceReference) -> QuizRun {
        var copy = self; copy.id = UUID(); copy.bank.id = UUID()
        for i in copy.bank.questions.indices { copy.bank.questions[i].id = UUID(); copy.bank.questions[i].references = copy.bank.questions[i].references.map(reference) }
        return copy
    }
}

public enum QuizBuilder {
    /// Distractors are other saved answers. This is an extractive exercise,
    /// never presented as an LLM-generated or independently verified exam.
    public static func make(cards: [StudyCard], limit: Int = 8, seed: UInt64 = 1, now: Date = Date()) -> QuizBank? {
        var unique: [StudyCard] = [], seen = Set<String>()
        for card in cards where !card.question.isEmpty && card.question.count <= 1000 && !card.answer.isEmpty && card.answer.count <= 500 {
            let key = card.answer.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping.lowercased()
            if !key.isEmpty, seen.insert(key).inserted { unique.append(card) }
        }
        guard unique.count >= 4 else { return nil }
        var random = seed
        func shuffled<T>(_ input: [T]) -> [T] {
            var result = input
            if result.count > 1 { for i in stride(from: result.count - 1, through: 1, by: -1) {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                result.swapAt(i, Int(random % UInt64(i + 1)))
            } }; return result
        }
        let chosen = shuffled(unique).prefix(min(12, max(1, limit)))
        let questions = chosen.map { card -> QuizQuestion in
            let others = shuffled(unique.filter { $0.answer != card.answer }).prefix(3).map(\.answer)
            let options = shuffled([card.answer] + others)
            return QuizQuestion(prompt: card.question, options: options, correctIndex: options.firstIndex(of: card.answer)!,
                explanation: "Risposta della flashcard: \(card.answer)", references: [card.source])
        }
        let bank = QuizBank(title: "Quiz dalle flashcard", questions: questions, provider: "Estrattivo · flashcard salvate", now: now)
        return bank.isValid ? bank : nil
    }
}

public extension AIEngineConfiguration {
    var quizURL: URL? {
        guard let lookup = lookupURL, var parts = URLComponents(url: lookup, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("lookup".count)) + "quiz"; return parts.url
    }
}
