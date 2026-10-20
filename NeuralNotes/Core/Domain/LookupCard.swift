import Foundation

public struct LookupRequest: Codable, Sendable {
    public var term: String
    public var sources: [IndexedChunk]
    public init(term: String, sources: [IndexedChunk]) { self.term = term.trimmingCharacters(in: .whitespacesAndNewlines); self.sources = sources }
    public var isValid: Bool {
        !term.isEmpty && term.count <= 120 && !term.contains(where: \.isNewline) && (1...40).contains(sources.count)
            && sources.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 8000 }) && sources.reduce(0, { $0 + $1.text.count }) <= 80000
    }
}

public struct LookupCard: Codable, Identifiable, Sendable {
    public var id: UUID
    public var term: String
    public var definition: String
    public var explanation: String
    public var examples: [String]
    public var relatedTerms: [String]
    public var references: [SourceReference]
    public var provider: String
    public var createdAt: Date
    public init(term: String, definition: String, explanation: String = "", examples: [String] = [], relatedTerms: [String] = [], references: [SourceReference], provider: String) {
        id = UUID(); self.term = term; self.definition = definition; self.explanation = explanation
        self.examples = examples; self.relatedTerms = relatedTerms; self.references = references; self.provider = provider; createdAt = Date()
    }
    public func validated(for request: LookupRequest) throws -> LookupCard {
        let normalized = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping.lowercased() }
        guard request.isValid, normalized(term) == normalized(request.term), !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              definition.count <= 8000, explanation.count <= 8000, examples.count <= 5, relatedTerms.count <= 5,
              (examples + relatedTerms).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1000 }) else { throw AIWireFailure.response }
        let allowed = request.sources.map(\.reference)
        guard !references.isEmpty, references.count <= 40, references.allSatisfy({ allowed.contains($0) }) else { throw AIWireFailure.citation }
        let pattern = try NSRegularExpression(pattern: "\\[(\\d+)\\]")
        for text in [definition, explanation] + examples + relatedTerms {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text), let index = Int(text[range]), (1...references.count).contains(index) else { throw AIWireFailure.citation }
            }
        }
        return self
    }
    public var text: String {
        ([term, definition, explanation] + examples.map { "• " + $0 } + (relatedTerms.isEmpty ? [] : ["Termini correlati: " + relatedTerms.joined(separator: ", ")])).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    public var artifact: AIArtifact { AIArtifact(id: id, text: text, references: references, provider: provider, createdAt: createdAt, task: .chat) }
}

public extension AIEngineConfiguration {
    var lookupURL: URL? {
        guard engine == .backend, let url, url.path.hasSuffix("/v1/study"), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("study".count)) + "lookup"; return parts.url
    }
}
