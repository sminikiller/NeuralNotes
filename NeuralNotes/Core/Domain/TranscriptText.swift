import Foundation

public struct TranscriptMinute: Identifiable, Equatable, Sendable {
    public var start: Double
    public var text: String
    public var id: Double { start }
}

public struct TranscriptCorrection: Codable, Equatable, Sendable {
    public var start: Double
    public var text: String
    public init(start: Double, text: String) { self.start = start; self.text = text }
}

public enum TranscriptText {
    public static func hasText(_ segments: [TranscriptSegment]) -> Bool {
        segments.contains { $0.start.isFinite && $0.start >= 0 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    public static func clock(_ seconds: Double) -> String {
        let value = Int(max(0, min(604800, seconds.isFinite ? seconds : 0)))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
    public static func minutes(_ segments: [TranscriptSegment]) -> [TranscriptMinute] {
        let sorted = segments.filter { $0.start.isFinite && $0.start >= 0 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.start < $1.start }
        let groups = Dictionary(grouping: sorted) { floor($0.start / 60.0) * 60.0 }
        return groups.keys.sorted().map { key in
            TranscriptMinute(start: key, text: (groups[key] ?? []).map(\.text).joined(separator: " "))
        }
    }
    public static func corrected(_ segments: [TranscriptSegment], corrections: [TranscriptCorrection]) -> [TranscriptSegment] {
        let keys = Set(corrections.map(\.start))
        var result = segments.filter { !keys.contains(floor($0.start / 60.0) * 60.0) }
        for correction in corrections where !correction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(TranscriptSegment(start: correction.start, duration: 60, text: correction.text))
        }
        return result.sorted { $0.start < $1.start }
    }
    public static func export(title: String, segments: [TranscriptSegment], complete: Bool) -> String {
        let state = complete ? "Trascrizione" : "Trascrizione parziale"
        let lines = minutes(segments).map { "[\(clock($0.start))] \($0.text)" }
        return "\(title)\n\(state) · riferimenti ogni minuto circa\n\n" + lines.joined(separator: "\n\n") + "\n"
    }
}

public extension AudioSession {
    /// Recover the readable projection from durable chunks if a legacy catalog
    /// contains the checkpoint data but an empty transcript array.
    var readableTranscript: [TranscriptSegment] {
        if TranscriptText.hasText(transcript) { return transcript }
        let raw = transcriptionChunks?.flatMap(\.segments) ?? []
        return TranscriptText.corrected(raw, corrections: transcriptCorrections ?? [])
    }
    var hasTranscriptText: Bool { TranscriptText.hasText(readableTranscript) }
    var hasCompletedTranscript: Bool {
        hasTranscriptText && (transcriptionComplete == true || (transcriptionChunks == nil && !transcript.isEmpty))
    }
}
