import Foundation

public enum ReviewRating: String, Codable, Sendable { case again, good, easy }

public struct StudyCard: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var question: String
    public var answer: String
    public var source: SourceReference
    public var dueAt: Date
    public var intervalDays: Int = 0
    public var reviewCount: Int = 0
    public var memory: Card?
    public init(question: String, answer: String, source: SourceReference, now: Date = Date()) {
        self.question = question; self.answer = answer; self.source = source; dueAt = now
    }
    /// A small deterministic schedule, not an adaptive memory model. Time is
    /// injectable so reviews, persistence and clock boundaries are testable.
    public mutating func review(_ rating: ReviewRating, now: Date = Date()) {
        reviewCount = min(1_000_000, max(0, reviewCount)) + 1
        intervalDays = min(365, max(0, intervalDays))
        switch rating {
        case .again:
            intervalDays = 0; dueAt = now.addingTimeInterval(10 * 60)
        case .good:
            intervalDays = intervalDays == 0 ? 1 : min(365, max(intervalDays + 1, Int(Double(intervalDays) * 2.5)))
            dueAt = now.addingTimeInterval(Double(intervalDays) * 86400)
        case .easy:
            intervalDays = intervalDays == 0 ? 3 : min(365, intervalDays * 3)
            dueAt = now.addingTimeInterval(Double(intervalDays) * 86400)
        }
    }
    /// FSRS-6 with the upstream default weights and deterministic scheduling.
    /// Old cards migrate lazily; their contents, IDs and current due date remain.
    public mutating func reviewAdaptive(_ rating: ReviewRating, now: Date = Date()) throws {
        let previous = memory ?? Card(due: dueAt, stability: reviewCount > 0 ? Double(max(1, intervalDays)) : 0,
            difficulty: reviewCount > 0 ? 5 : 0, scheduledDays: Double(max(0, intervalDays)), reps: max(0, reviewCount),
            state: reviewCount > 0 ? .review : .new,
            lastReview: reviewCount > 0 ? dueAt.addingTimeInterval(-Double(max(1, intervalDays)) * 86400) : nil)
        guard previous.stability.isFinite, previous.difficulty.isFinite, previous.elapsedDays.isFinite,
              previous.scheduledDays.isFinite else { throw LibraryFailure.corruptDocument }
        let engine = FSRS(parameters: FSRSParameters(w: FSRSDefaults.defaultWv6, enableFuzz: false))
        let grade: Rating = rating == .again ? .again : rating == .easy ? .easy : .good
        let next = try engine.next(card: previous, now: now, grade: grade).card
        memory = next; dueAt = next.due; intervalDays = max(0, Int(next.scheduledDays.rounded())); reviewCount = next.reps
    }
}

public enum StudyCardBuilder {
    /// Extractive cloze questions: the answer always occurs in the actual source.
    public static func make(from chunks: [IndexedChunk], limit: Int = 30, now: Date = Date()) -> [StudyCard] {
        var cards: [StudyCard] = [], seen = Set<String>()
        for chunk in chunks {
            for sentence in chunk.text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")) {
                let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (30...1200).contains(text.count), seen.insert(text.lowercased()).inserted else { continue }
                let words = text.split { !$0.isLetter }.map(String.init).filter { $0.count >= 6 }
                guard let answer = words.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }).first,
                      let range = text.range(of: answer) else { continue }
                var question = text; question.replaceSubrange(range, with: "[ … ]")
                cards.append(StudyCard(question: question, answer: answer, source: chunk.reference, now: now))
                if cards.count >= max(1, min(limit, 100)) { return cards }
            }
        }
        return cards
    }
}
