import Foundation

public enum AudioReplayMode: String, Codable, CaseIterable, Sendable {
    case follow, showAll, keyPoints
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .follow }
    public var title: String {
        switch self { case .follow: return "Segui in tempo reale"; case .showAll: return "Mostra tutto"; case .keyPoints: return "Salta ai punti chiave" }
    }
}

public extension AudioReplay {
    /// A long gap in timed transcript metadata supplies a navigation point,
    /// not proof of silence. Nothing removes or silently skips recorded audio.
    static func keyPoints(_ session: AudioSession, minimumPause: Double = 8) -> [Double] {
        guard session.duration.isFinite, session.duration > 0, minimumPause.isFinite, minimumPause > 0 else { return [] }
        var values = [0.0] + (session.bookmarks ?? []).filter(\.isValid).map(\.seconds)
        let text = session.transcript.filter { $0.start.isFinite && $0.duration.isFinite && $0.start >= 0 && $0.duration >= 0 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.start < $1.start }
        var end = 0.0
        for entry in text {
            if entry.start - end >= minimumPause { values.append(entry.start) }
            end = max(end, entry.start + entry.duration)
        }
        var previous = -Double.infinity
        return values.filter { $0.isFinite && $0 >= 0 && $0 < session.duration }.sorted().filter { value in
            guard value - previous > 0.1 else { return false }; previous = value; return true
        }
    }
    static func keyPoint(_ direction: Int, from seconds: Double, session: AudioSession) -> Double? {
        guard seconds.isFinite else { return nil }
        let points = keyPoints(session)
        return direction > 0 ? points.first { $0 > seconds + 0.25 } : points.last { $0 < seconds - 0.25 }
    }
    static func current(signatures: [String], anchors: [StrokeAnchor], sessionID: UUID, seconds: Double) -> [Int] {
        guard seconds.isFinite else { return [] }
        let eligible = anchors.filter { $0.audioSessionID == sessionID && $0.seconds.isFinite && $0.seconds <= seconds && seconds - $0.seconds <= 2 }
        guard let latest = eligible.map(\.seconds).max() else { return [] }
        let hot = Set(eligible.filter { abs($0.seconds - latest) <= 0.05 }.map(\.signature))
        return signatures.indices.filter { hot.contains(signatures[$0]) }
    }
}
