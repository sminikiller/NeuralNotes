import Foundation

public enum PaperStyle: String, Codable, CaseIterable, Sendable {
    case plain, ruled, grid, dotted, cornell, weekly, music, isometric, millimeter, mindMap
    public var title: String {
        switch self {
        case .plain: return "Libero"
        case .ruled: return "Rigato"
        case .grid: return "Quadrettato"
        case .dotted: return "Puntinato"
        case .cornell: return "Cornell"; case .weekly: return "Agenda settimanale"; case .music: return "Pentagramma"
        case .isometric: return "Isometrico"; case .millimeter: return "Millimetrato"; case .mindMap: return "Mappa concettuale"
        }
    }
}

public struct TextElement: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var x: Double = 48
    public var y: Double = 64
    public var width: Double = 480
    public var fontSize: Double = 24
    public var rtf: Data?
    public var rotation: Double?
    public var background: InkColor?
    public var pageLink: PageLinkTarget?
    public init(text: String) { self.text = text }
}

public struct ImageElement: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var file: String
    public var x: Double = 48
    public var y: Double = 120
    public var width: Double
    public var height: Double
    public var crop: NormalizedCrop?
    public var rotation: Double?
    public init(file: String, width: Double, height: Double) {
        self.file = file; self.width = width; self.height = height
    }
}

public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var file: String
    public var originalName: String
    public var type: String
    public var sha256: String
    public init(file: String, originalName: String, type: String, sha256: String) {
        self.file = file; self.originalName = originalName; self.type = type; self.sha256 = sha256
    }
}

public struct StrokeAnchor: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var signature: String
    public var audioSessionID: UUID
    public var seconds: Double
    public init(signature: String, audioSessionID: UUID, seconds: Double) {
        self.signature = signature; self.audioSessionID = audioSessionID; self.seconds = seconds
    }
}

/// Coordinates always refer to the unzoomed, portrait page, in points.
public struct PageSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var revision: Int = 0
    public var width: Double = 768
    public var height: Double = 1024
    public var paper: PaperStyle = .plain
    public var drawingFile: String?
    public var previousDrawingFile: String?
    public var pdfFile: String?
    public var pdfIndex: Int?
    public var texts: [TextElement] = []
    public var images: [ImageElement] = []
    public var anchors: [StrokeAnchor] = []
    public var recognizedText: String = ""
    // Optional fields keep v1 packages created before 0.3 decodable.
    public var title: String?
    public var isBookmarked: Bool?
    public var shapes: [ShapeElement]?
    public var appearance: PaperAppearance?
    public var lastEditedAt: Double?
    public var pdfMarkups: [PDFMarkup]?
    public var tapes: [StudyTape]?
    public var objectOrder: [UUID]?
    public var lockedObjects: [UUID]?
    public var aboveInkObjects: [UUID]?
    public init(id: UUID = UUID()) { self.id = id }
}

public struct AudioTimelineSegment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var file: String
    public var start: Double
    public var duration: Double = 0
    public var hostStart: Double
    public var endReason: String?
    public var codec: String?
    public var bitRate: Int?
    public var originalBytes: Int64?
    public init(file: String, start: Double, hostStart: Double) {
        self.file = file; self.start = start; self.hostStart = hostStart
    }
}

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var start: Double
    public var duration: Double
    public var text: String
    public init(start: Double, duration: Double, text: String) {
        self.start = start; self.duration = duration; self.text = text
    }
}

public struct AudioSession: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var createdAt = Date()
    public var segments: [AudioTimelineSegment] = []
    public var transcript: [TranscriptSegment] = []
    public var state = "paused"
    public var revision: Int? = nil
    public var transcriptionChunks: [TranscriptionChunk]?
    public var transcriptCorrections: [TranscriptCorrection]?
    public var transcriptionComplete: Bool?
    public var bookmarks: [AudioBookmark]?
    public var isArchived: Bool?
    public var trashedAt: Date?
    public var duration: Double { segments.map { $0.start + $0.duration }.max() ?? 0 }
    public init(title: String) { self.title = title }
}

public struct DocumentCatalog: Codable, Sendable {
    public var schemaVersion = 1
    public var attachments: [Attachment] = []
    public var sessions: [AudioSession] = []
    public var coverImageFile: String?
    public var studyCards: [StudyCard]?
    public var adaptiveReview: Bool?
    public var defaultPageTemplate: PageTemplate?
    public var editorWorkspaces: NotebookWorkspaces?
    public var coverDesign: CoverDesign?
    public var coverUsesLastEditedPage: Bool?
    public var conversation: [AIConversationTurn]?
    public var organization: NotebookOrganization?
    public var glossary: [GlossaryEntry]?
    public var lensCache: [CachedLensAnswer]?
    public var sections: [NotebookSection]?
    public var reviewLog: [StudyReviewEvent]?
    public var activeQuiz: QuizRun?
    public var quizHistory: [QuizRun]?
    public init() { }
}
