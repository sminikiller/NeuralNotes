import Foundation

/// Flashcards proposed by a model from selected sources. They stay drafts until
/// the student keeps them: every card cites the source it was derived from.
public struct FlashcardRequest: Codable, Sendable {
    public var sources: [IndexedChunk]
    public var count: Int
    public var focus: String
    public init(sources: [IndexedChunk], count: Int = 10, focus: String = "") {
        self.sources = sources; self.count = count; self.focus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var isValid: Bool {
        (1...20).contains(count) && focus.count <= 300 && !focus.contains(where: \.isNewline)
            && LookupRequest(term: "Flashcard", sources: sources).isValid
    }
    static let instruction = "Crea al massimo count flashcard di ripasso dalle fonti. Ogni flashcard contiene una sola idea: una domanda breve e precisa (question) e una risposta di una o due frasi (answer), con citations. Niente domande sì/no, niente duplicati, niente fatti assenti dalle fonti. Se le fonti non bastano crea meno carte. Se focus non è vuoto, concentrati su quell'argomento."
}

public struct FlashcardDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var question: String
    public var answer: String
    public var references: [SourceReference]
    public init(id: UUID = UUID(), question: String, answer: String, references: [SourceReference]) {
        self.id = id; self.question = question; self.answer = answer; self.references = references
    }
    public var isValid: Bool {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines), a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && q.count <= 1000 && !a.isEmpty && a.count <= 2000 && (1...40).contains(references.count)
    }
    /// The card the student keeps, scheduled from now and linked to its first source.
    public func card(now: Date = Date()) -> StudyCard? {
        guard isValid, let source = references.first else { return nil }
        return StudyCard(question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                         answer: answer.trimmingCharacters(in: .whitespacesAndNewlines), source: source, now: now)
    }
}

public struct FlashcardSet: Codable, Equatable, Sendable {
    public var cards: [FlashcardDraft]
    public var provider: String
    public init(cards: [FlashcardDraft], provider: String) { self.cards = cards; self.provider = provider }
    public func validated(for request: FlashcardRequest) throws -> FlashcardSet {
        guard request.isValid, (1...request.count).contains(cards.count), cards.allSatisfy(\.isValid),
              Set(cards.map(\.id)).count == cards.count, !provider.isEmpty, provider.count <= 240 else { throw AIWireFailure.response }
        let allowed = request.sources.map(\.reference), pattern = try NSRegularExpression(pattern: "\\[(\\d+)\\]")
        for card in cards {
            guard card.references.allSatisfy({ allowed.contains($0) }) else { throw AIWireFailure.citation }
            for text in [card.question, card.answer] {
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range(at: 1), in: text), let value = Int(text[range]),
                          (1...card.references.count).contains(value) else { throw AIWireFailure.citation }
                }
            }
        }
        // The same question twice is noise in a review deck: keep the first one.
        var seen = Set<String>(), unique: [FlashcardDraft] = []
        for card in cards where seen.insert(card.question.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping.lowercased()).inserted {
            unique.append(card)
        }
        return FlashcardSet(cards: unique, provider: provider)
    }
}

public extension AIEngineConfiguration {
    /// Schede, quiz e flashcard: the backend needs its endpoints, personal keys call the provider directly.
    var supportsStructuredStudy: Bool { engine == .backend ? lookupURL != nil : engine != .offline }
    /// Web search needs the backend or a Responses API key with the web search tool.
    var supportsWebResearch: Bool { engine == .backend ? researchURL != nil : engine == .openAI || engine == .compatibleResponses }
    var cardsURL: URL? {
        guard let lookup = lookupURL, var parts = URLComponents(url: lookup, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("lookup".count)) + "cards"; return parts.url
    }
}

public extension FlashcardDraft {
    /// Offline card from a Lens answer: a real question about the subject and the
    /// first sentences of the answer, never the command that produced it.
    static func local(subject: String, answer: String, reference: SourceReference) -> FlashcardDraft {
        let topic = subject.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) ?? ""
        let shortTopic = topic.count > 80 ? String(topic.prefix(80)) + "…" : topic
        var sentences: [String] = [], current = ""
        for character in answer.replacingOccurrences(of: "\n", with: " ") {
            current.append(character)
            if ".!?".contains(character) { sentences.append(current.trimmingCharacters(in: .whitespaces)); current = ""; if sentences.count == 2 { break } }
        }
        if sentences.count < 2, !current.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(current.trimmingCharacters(in: .whitespaces)) }
        let summary = sentences.joined(separator: " ")
        return FlashcardDraft(question: shortTopic.isEmpty ? "Che cosa dicono le fonti?" : "Che cosa sai di «\(shortTopic)»?",
                              answer: String(summary.prefix(600)), references: [reference])
    }
}
