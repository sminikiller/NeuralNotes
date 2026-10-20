import Foundation

public struct AudioBookmark: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var seconds: Double
    public init(title: String, seconds: Double) { self.title = title; self.seconds = seconds }
    public var isValid: Bool { !title.isEmpty && title.count <= 120 && seconds.isFinite && seconds >= 0 }
}

public enum AudioReplay {
    /// Unlinked ink remains visible. Linked ink appears at its recorded timestamp.
    public static func visible(signatures: [String], anchors: [StrokeAnchor], sessionID: UUID, seconds: Double) -> [Int] {
        let timeline = Dictionary(anchors.filter { $0.audioSessionID == sessionID }.map { ($0.signature, $0.seconds) }, uniquingKeysWith: min)
        return signatures.indices.filter { index in timeline[signatures[index]].map { $0 <= seconds } ?? true }
    }
}
