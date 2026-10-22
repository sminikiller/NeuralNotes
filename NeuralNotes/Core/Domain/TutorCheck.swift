import Foundation

/// "Interrogami": the student answers a flashcard in their own words and the
/// model judges the answer only against the card and the text it came from.
public enum TutorCheck {
    public enum Verdict: String, Sendable { case correct, partial, wrong }

    public static func request(card: StudyCard, answer: String, context: [IndexedChunk]) -> AIRequest? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1500 else { return nil }
        let expected = IndexedChunk(text: "Risposta attesa della flashcard: " + String(card.answer.prefix(2000)), reference: card.source)
        let related = context.filter { chunk in
            if let page = card.source.pageID { return chunk.reference.pageID == page }
            if let audio = card.source.audioSessionID { return chunk.reference.audioSessionID == audio }
            return false
        }.prefix(8).map { IndexedChunk(text: String($0.text.prefix(4000)), reference: $0.reference, kind: $0.kind) }
        let question = """
        Interrogazione. Domanda: «\(card.question.prefix(1000))»
        Risposta dello studente: «\(trimmed)»
        Valuta la risposta solo rispetto alle fonti. Inizia con una sola parola tra Corretta, Parziale o Da rivedere; poi spiega in due o tre frasi cosa manca o cosa è sbagliato e riporta la risposta corretta con le citazioni.
        """
        return AIRequest(task: .chat, question: question, sources: [expected] + related)
    }

    public static func verdict(_ text: String) -> Verdict? {
        let start = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        if start.hasPrefix("corretta") || start.hasPrefix("corretto") { return .correct }
        if start.hasPrefix("parziale") || start.hasPrefix("parzialmente") { return .partial }
        if start.hasPrefix("da rivedere") || start.hasPrefix("errata") || start.hasPrefix("sbagliata") { return .wrong }
        return nil
    }

    /// A suggestion only: the student still chooses the rating that schedules the card.
    public static func suggestedRating(_ verdict: Verdict) -> ReviewRating {
        switch verdict {
        case .correct: return .good
        case .partial: return .hard
        case .wrong: return .again
        }
    }
}
