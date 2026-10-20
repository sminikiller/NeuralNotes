import Foundation

public struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var term: String
    public var definition: String
    public var references: [SourceReference]
    public var updatedAt = Date()
    public init(term: String, definition: String, references: [SourceReference]) {
        self.term = term; self.definition = definition; self.references = references
    }
    public var isValid: Bool { !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && term.count <= 120 && !definition.isEmpty && definition.count <= 16000 && references.count <= 40 }
}

public struct CachedLensAnswer: Codable, Sendable {
    public var key: String
    public var artifact: AIArtifact
    public init(key: String, artifact: AIArtifact) { self.key = key; self.artifact = artifact }
}
