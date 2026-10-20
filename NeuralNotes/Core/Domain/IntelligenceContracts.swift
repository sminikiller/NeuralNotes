import Foundation

public struct OCRTextRegion: Sendable {
    public let text: String
    public let confidence: Float
    public let x: Double, y: Double, width: Double, height: Double
    public init(text: String, confidence: Float, x: Double, y: Double, width: Double, height: Double) {
        self.text = text; self.confidence = confidence
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public protocol OCRService: Sendable {
    func recognize(image: Data) async throws -> [OCRTextRegion]
}

@MainActor
public protocol TranscriptionService: AnyObject {
    func transcribe(url: URL, language: String) async throws -> [TranscriptSegment]
}

public struct SourceReference: Codable, Equatable, Sendable {
    public let documentID: UUID
    public let pageID: UUID?
    public let audioSessionID: UUID?
    public let seconds: Double?
    public let pageRevision: Int?
    public init(documentID: UUID, pageID: UUID? = nil, audioSessionID: UUID? = nil, seconds: Double? = nil, pageRevision: Int? = nil) {
        self.documentID = documentID; self.pageID = pageID
        self.audioSessionID = audioSessionID; self.seconds = seconds
        self.pageRevision = pageRevision
    }
}

public struct IndexedChunk: Codable, Sendable {
    public let text: String
    public let reference: SourceReference
    public init(text: String, reference: SourceReference) { self.text = text; self.reference = reference }
}

public enum AITask: String, Codable, CaseIterable, Sendable {
    case summarize, outline, flashcards, quiz, chat, compare
    public var title: String {
        switch self {
        case .summarize: return "Riassunto"
        case .outline: return "Schema"
        case .flashcards: return "Flashcard"
        case .quiz: return "Quiz"
        case .chat: return "Chat"
        case .compare: return "Confronta fonti"
        }
    }
}

public struct AIRequest: Codable, Sendable {
    public let task: AITask
    public let question: String
    public let sources: [IndexedChunk]
    public init(task: AITask, question: String, sources: [IndexedChunk]) {
        self.task = task; self.question = question; self.sources = sources
    }
}

public struct AIArtifact: Codable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let references: [SourceReference]
    public let provider: String
    public let createdAt: Date
    public let task: AITask?
    public init(id: UUID = UUID(), text: String, references: [SourceReference], provider: String, createdAt: Date = Date(), task: AITask? = nil) {
        self.id = id; self.text = text; self.references = references; self.provider = provider; self.createdAt = createdAt
        self.task = task
    }
}

public protocol AIProvider: Sendable {
    func generate(_ request: AIRequest) async throws -> AIArtifact
}

/// Optional contracts; no fake vectors, semantic ranking or local model are supplied.
public protocol LocalAIProvider: AIProvider { var isAvailable: Bool { get async } }
public protocol EmbeddingService: Sendable { func embed(_ texts: [String]) async throws -> [[Float]] }
public protocol DocumentIndexingService: Sendable { func index(documentID: UUID) async throws -> [IndexedChunk] }
public protocol RetrievalService: Sendable {
    func retrieve(question: String, from chunks: [IndexedChunk], limit: Int) async throws -> [IndexedChunk]
}
