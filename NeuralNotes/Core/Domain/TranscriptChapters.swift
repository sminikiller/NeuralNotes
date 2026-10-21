import Foundation

public struct TranscriptChapter: Identifiable, Equatable, Sendable {
    public var id: Double { start }
    public var start: Double
    public var title: String
    public var minutes: [TranscriptMinute]
}

public enum TranscriptChapters {
    /// Time-based organization, not an AI summary. Every recognized phrase is
    /// retained once; bookmark titles are supplied by the user, never invented.
    public static func make(session: AudioSession) -> [TranscriptChapter] {
        let segments = session.readableTranscript.filter { $0.start.isFinite && (0...604800).contains($0.start) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.start < $1.start }
        let last = segments.map { $0.start + ($0.duration.isFinite ? max(0, min(3600, $0.duration)) : 0) }.max() ?? 0
        let duration = max(last, session.duration.isFinite ? max(0, min(604800, session.duration)) : 0)
        let bookmarks = (session.bookmarks ?? []).filter { $0.isValid && $0.seconds <= duration }
        let named = Dictionary(grouping: bookmarks, by: \.seconds)
        var starts: Set<Double> = [0]
        for start in stride(from: 300.0, through: duration, by: 300.0) { starts.insert(start) }
        starts.formUnion(bookmarks.map(\.seconds))
        let boundaries = starts.sorted()
        var grouped: [Int: [TranscriptSegment]] = [:], index = 0
        for segment in segments {
            while index + 1 < boundaries.count && boundaries[index + 1] <= segment.start { index += 1 }
            grouped[index, default: []].append(segment)
        }
        return boundaries.indices.compactMap { index in
            let start = boundaries[index], values = grouped[index] ?? []
            guard !values.isEmpty || named[start] != nil else { return nil }
            let title = named[start].map { String($0.map(\.title).joined(separator: " · ").prefix(240)) } ?? "Capitolo · \(TranscriptText.clock(start))"
            var minutes = TranscriptText.minutes(values)
            for i in minutes.indices { minutes[i].start = max(start, minutes[i].start) }
            return TranscriptChapter(start: start, title: title, minutes: minutes)
        }
    }
    public static func markdown(session: AudioSession) -> String {
        let title = session.title.replacingOccurrences(of: "\n", with: " ")
        let state = session.hasCompletedTranscript ? "Trascrizione completa" : "Trascrizione parziale"
        var result = "# \(title)\n\n\(state) · capitoli temporali e segnalibri personali.\n"
        for chapter in make(session: session) {
            result += "\n## [\(TranscriptText.clock(chapter.start))] \(chapter.title.replacingOccurrences(of: "\n", with: " "))\n\n"
            result += chapter.minutes.map { "[\(TranscriptText.clock($0.start))] \($0.text)" }.joined(separator: "\n\n") + "\n"
        }
        return result
    }
}
