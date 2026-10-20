import Foundation

public struct AIConversationTurn: Codable, Identifiable, Sendable {
    public let id: UUID
    public let question: String
    public let answer: AIArtifact
    public init(question: String, answer: AIArtifact) { id = UUID(); self.question = question; self.answer = answer }
}
