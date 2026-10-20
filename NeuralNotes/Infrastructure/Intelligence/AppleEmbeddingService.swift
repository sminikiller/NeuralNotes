import Foundation
import NaturalLanguage
import NeuralNotesCore

enum EmbeddingFailure: LocalizedError {
    case unavailable, emptyQuery
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Il modello di embedding italiano non è disponibile su questo dispositivo. Puoi usare la ricerca testuale."
        case .emptyQuery: return "La domanda non contiene termini rappresentabili dal modello locale. Prova altre parole o la ricerca testuale."
        }
    }
}

/// Real OS-provided embeddings. Uses a sentence model when present, otherwise
/// averages actual Italian word vectors. No fabricated vectors or silent lexical fallback.
actor AppleEmbeddingService: EmbeddingService {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let sentenceModel = NLEmbedding.sentenceEmbedding(for: .italian)
        guard let model = sentenceModel ?? NLEmbedding.wordEmbedding(for: .italian) else {
            throw EmbeddingFailure.unavailable
        }
        var result: [[Float]] = []
        for text in texts {
            try Task.checkCancellation()
            let vector: [Double]
            if sentenceModel != nil, let sentence = model.vector(for: text) {
                vector = sentence
            } else {
                let tokenizer = NLTokenizer(unit: .word)
                tokenizer.string = text; tokenizer.setLanguage(.italian)
                var sum = Array(repeating: 0.0, count: model.dimension)
                var count = 0
                tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                    let word = String(text[range]).lowercased()
                    guard word.count > 2, let values = model.vector(for: word), values.count == sum.count else { return true }
                    for index in sum.indices { sum[index] += values[index] }
                    count += 1
                    return true
                }
                vector = count == 0 ? sum : sum.map { $0 / Double(count) }
            }
            result.append(vector.map(Float.init))
            await Task.yield()
        }
        return result
    }
}

struct SemanticRetrievalService: RetrievalService {
    let embeddings: any EmbeddingService

    func retrieve(question: String, from chunks: [IndexedChunk], limit: Int) async throws -> [IndexedChunk] {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EmbeddingFailure.emptyQuery }
        let vectors = try await embeddings.embed([question] + chunks.map(\.text))
        guard vectors.count == chunks.count + 1 else { throw EmbeddingFailure.unavailable }
        guard let query = vectors.first, query.allSatisfy(\.isFinite), query.contains(where: { $0 != 0 }) else { throw EmbeddingFailure.emptyQuery }
        let queryLength = sqrt(query.reduce(0.0) { $0 + Double($1 * $1) })
        let scores = chunks.indices.compactMap { index -> (Int, Double)? in
            let value = vectors[index + 1]
            guard value.count == query.count, value.allSatisfy(\.isFinite) else { return nil }
            let length = sqrt(value.reduce(0.0) { $0 + Double($1 * $1) })
            guard length > 0 else { return nil }
            let product = zip(query, value).reduce(0.0) { $0 + Double($1.0 * $1.1) }
            return (index, product / (queryLength * length))
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        return scores.prefix(max(0, limit)).map { chunks[$0.0] }
    }
}
