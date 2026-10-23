import Foundation
import NeuralNotesCore

/// Deterministic text processing, explicitly distinct from generative AI. Every
/// output sentence comes from a supplied source; no model or embedding is claimed.
struct ExtractiveStudyProvider: AIProvider {
    private static let stopWords = Set("a ad al alla allo alle agli ai anche che chi ci come con da dal dalla dalle dei del della delle di e ed è era essere fa fra gli ha hai hanno i il in io la le lo ma mi ne nel nella nelle noi non o per più quale quando quello questa queste questo qui se sei si sia sono su sul sulla tra tu un una uno vi voi the and of to is in it for on that this are as at by from with".split(separator: " ").map(String.init))

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 3 && !stopWords.contains($0) }
    }

    func generate(_ request: AIRequest) async throws -> AIArtifact {
        let operation = Task<AIArtifact, Error>.detached(priority: .utility) { () async throws -> AIArtifact in
            try Task.checkCancellation()
            var frequency: [String: Int] = [:]
            var candidates: [(text: String, reference: SourceReference, order: Int)] = []
            for chunk in request.sources {
                try Task.checkCancellation()
                for word in Self.words(chunk.text) { frequency[word, default: 0] += 1 }
                for sentence in chunk.text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")) {
                    let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean.count >= 20 {
                        candidates.append((String(clean.prefix(1200)), chunk.reference, candidates.count))
                    }
                }
            }
            guard !candidates.isEmpty else { throw StudyFailure.emptySources }
            let query = Set(Self.words(request.question))
            func score(_ value: (text: String, reference: SourceReference, order: Int)) -> Double {
                let terms = Set(Self.words(value.text))
                let matching = terms.intersection(query).count
                var weight: Double = 0
                for term in terms { weight += Double(frequency[term, default: 0]) }
                let length: Double = sqrt(Double(max(terms.count, 1)))
                return Double(matching * 100) + weight / length
            }
            var seen = Set<String>()
            let ranked = candidates.sorted {
                let a = score($0), b = score($1)
                return a == b ? $0.order < $1.order : a > b
            }.filter { seen.insert($0.text).inserted }
            let selected = Array(ranked.prefix(request.task == .chat ? 5 : 10))
            var references: [SourceReference] = []
            func cite(_ source: SourceReference) -> String {
                if !references.contains(source) { references.append(source) }
                return "[\((references.firstIndex(of: source) ?? 0) + 1)]"
            }
            let lines: [String]
            switch request.task {
            case .summarize:
                lines = selected.sorted { $0.order < $1.order }.map { "• \($0.text). \(cite($0.reference))" }
            case .outline:
                lines = selected.map { value in
                    let keyword = Self.words(value.text).max { frequency[$0, default: 0] < frequency[$1, default: 0] } ?? "Appunto"
                    return "\(keyword.capitalized)\n\(value.text). \(cite(value.reference))"
                }
            case .flashcards, .quiz:
                lines = selected.compactMap { value in
                    guard let keyword = Self.words(value.text).filter({ $0.count >= 5 }).max(by: { $0.count < $1.count }),
                          let range = value.text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
                    var question = value.text; question.replaceSubrange(range, with: "[ … ]")
                    return "Completa: \(question)\nRisposta: \(keyword) \(cite(value.reference))"
                }
            case .chat:
                guard !query.isEmpty else { throw StudyFailure.questionRequired }
                lines = selected.filter { !Set(Self.words($0.text)).isDisjoint(with: query) }
                    .map { "«\($0.text)» \(cite($0.reference))" }
            case .compare:
                var documents: [UUID] = []
                for value in selected where !documents.contains(value.reference.documentID) { documents.append(value.reference.documentID) }
                lines = documents.map { id in
                    "Fonte \(id.uuidString.prefix(8))\n" + selected.filter { $0.reference.documentID == id }.prefix(3)
                        .map { "• \($0.text). \(cite($0.reference))" }.joined(separator: "\n")
                }
            }
            let introduction = request.task == .chat ? "Passaggi collegati alle parole della domanda; non è una risposta generata:" : "Estrazione dalle fonti, senza modello generativo:"
            let body = lines.isEmpty ? "Nessun passaggio corrispondente nelle fonti selezionate." : lines.joined(separator: "\n\n")
            return AIArtifact(text: introduction + "\n\n" + body, references: references, provider: "Sintesi estrattiva locale", task: request.task)
        }
        return try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }
}

enum StudyFailure: LocalizedError {
    case questionRequired, emptySources
    var errorDescription: String? {
        switch self {
        case .questionRequired: return "Scrivi una domanda con almeno una parola significativa."
        case .emptySources: return "Le fonti non contengono frasi abbastanza lunghe da elaborare. Aggiungi testo o riconosci una pagina."
        }
    }
}
