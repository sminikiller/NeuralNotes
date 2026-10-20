import Foundation

public enum ReviewRating: String, Sendable { case again, good, easy }

public struct StudyCard: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var question: String
    public var answer: String
    public var source: SourceReference
    public var dueAt: Date
    public var intervalDays: Int = 0
    public var reviewCount: Int = 0
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
