import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// One chapter of the "sbobina": the model rewrites the phrases of that time
/// span as clean study notes. A nil text means the block is still to be done.
public struct LectureNotesBlock: Codable, Equatable, Identifiable, Sendable {
    public var start: Double
    public var end: Double
    public var title: String
    public var text: String?
    public var provider: String?
    public var id: Double { start }
    public init(start: Double, end: Double, title: String, text: String? = nil, provider: String? = nil) {
        self.start = start; self.end = end; self.title = title; self.text = text; self.provider = provider
    }
}

/// Lecture notes stored with their audio session. The fingerprint ties them to
/// the transcript they were written from: corrections make them stale, never wrong.
public struct LectureNotes: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var blocks: [LectureNotesBlock]
    public var updatedAt: Date
    public init(fingerprint: String, blocks: [LectureNotesBlock], updatedAt: Date = Date()) {
        self.fingerprint = fingerprint; self.blocks = blocks; self.updatedAt = updatedAt
    }
    public var completedCount: Int { blocks.filter { $0.text != nil }.count }
    public var isComplete: Bool { !blocks.isEmpty && completedCount == blocks.count }
    public var isValid: Bool {
        fingerprint.count == 64 && blocks.count <= 2200 && updatedAt.timeIntervalSince1970.isFinite
            && blocks.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.title.count <= 240
                && ($0.text?.count ?? 0) <= 40_000 && ($0.provider?.count ?? 0) <= 240 }
            && zip(blocks, blocks.dropFirst()).allSatisfy { $0.start < $1.start }
    }
}

public enum LectureNotesPlanner {
    static let instruction = "Riscrivi questo blocco di lezione come appunti di studio puliti in italiano: titoli brevi, elenchi puntati, definizioni ed esempi importanti. Mantieni l’ordine e tutti i concetti presenti; elimina ripetizioni, intercalari e frasi spezzate. Non aggiungere fatti che non sono nelle fonti. Dopo ogni punto cita la frase di origine con [n]. Le fonti sono la trascrizione automatica: se una parola sembra riconosciuta male, non inventare e segnala il dubbio."

    public static func fingerprint(_ session: AudioSession) -> String {
        var hash = SHA256()
        for segment in session.readableTranscript { hash.update(data: Data("\(segment.start)|\(segment.text)\n".utf8)) }
        for bookmark in session.bookmarks ?? [] { hash.update(data: Data("b|\(bookmark.seconds)|\(bookmark.title)\n".utf8)) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Blocks follow the transcript chapters: five minutes, or the student's bookmarks.
    public static func plan(_ session: AudioSession) -> [LectureNotesBlock] {
        let chapters = TranscriptChapters.make(session: session).filter { !$0.minutes.isEmpty }
        let ends = session.readableTranscript.map { $0.start + max(0, min(3600, $0.duration.isFinite ? $0.duration : 0)) }
        let last = max(session.duration.isFinite ? session.duration : 0, ends.max() ?? 0)
        return chapters.enumerated().map { index, chapter in
            let end = index + 1 < chapters.count ? chapters[index + 1].start : max(chapter.start, last)
            return LectureNotesBlock(start: chapter.start, end: end, title: chapter.title)
        }
    }

    /// Notes are kept when the transcript is unchanged; otherwise a new plan starts.
    public static func resume(_ session: AudioSession) -> LectureNotes {
        let print = fingerprint(session)
        if let notes = session.lectureNotes, notes.fingerprint == print, notes.isValid { return notes }
        return LectureNotes(fingerprint: print, blocks: plan(session))
    }

    /// The phrases of one block as numbered sources, each with its own timestamp,
    /// grouped so that a long chapter never exceeds forty sources.
    public static func request(for block: LectureNotesBlock, session: AudioSession, documentID: UUID) -> AIRequest? {
        let phrases = session.readableTranscript.filter {
            $0.start.isFinite && $0.start >= block.start && ($0.start < block.end || ($0.start == block.end && block.end == block.start))
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.start < $1.start }
        guard !phrases.isEmpty else { return nil }
        let size = max(1, (phrases.count + 39) / 40)
        let sources = stride(from: 0, to: phrases.count, by: size).map { offset -> IndexedChunk in
            let group = phrases[offset..<min(phrases.count, offset + size)]
            let text = group.map { "[\(TranscriptText.clock($0.start))] \($0.text)" }.joined(separator: " ")
            return IndexedChunk(text: String(text.prefix(8000)),
                                reference: SourceReference(documentID: documentID, audioSessionID: session.id, seconds: group.first!.start), kind: .audio)
        }
        let named = block.title.hasPrefix("Capitolo · ") ? "" : " Titolo scelto dallo studente per questo capitolo: \(block.title.prefix(240))."
        return AIRequest(task: .outline, question: instruction + named, sources: sources)
    }

    /// Citation markers become the time of the cited phrase, clickable in the reader.
    public static func notesText(from artifact: AIArtifact) -> String {
        var text = artifact.text
        guard let pattern = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else { return text }
        for match in pattern.matches(in: artifact.text, range: NSRange(artifact.text.startIndex..., in: artifact.text)).reversed() {
            guard let numberRange = Range(match.range(at: 1), in: artifact.text), let range = Range(match.range, in: text) else { continue }
            let number = Int(artifact.text[numberRange]) ?? 0
            let seconds = artifact.references.indices.contains(number - 1) ? artifact.references[number - 1].seconds : nil
            text.replaceSubrange(range, with: seconds.map { "[\(TranscriptText.clock($0))]" } ?? "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func markdown(title: String, notes: LectureNotes) -> String {
        let providers = Set(notes.blocks.compactMap(\.provider)).sorted().joined(separator: ", ")
        let state = notes.isComplete ? "Sbobina completa" : "Sbobina parziale: \(notes.completedCount) blocchi su \(notes.blocks.count)"
        var result = "# Sbobina · \(title.replacingOccurrences(of: "\n", with: " "))\n\n\(state)" + (providers.isEmpty ? "" : " · \(providers)") + ". Rielaborazione AI della trascrizione: controlla i passaggi importanti sull’audio.\n"
        for block in notes.blocks {
            result += "\n## [\(TranscriptText.clock(block.start))] \(block.title.replacingOccurrences(of: "\n", with: " "))\n\n"
            result += (block.text.map { $0.isEmpty ? "_Nessun testo riconosciuto in questo capitolo._" : $0 } ?? "_Capitolo non ancora elaborato._") + "\n"
        }
        return result
    }

    /// Text for new notebook pages: whole paragraphs, at most `limit` characters each.
    public static func pages(_ markdown: String, limit: Int = 2400) -> [String] {
        let maximum = max(200, limit)
        var pages: [String] = [], current = ""
        for paragraph in markdown.components(separatedBy: "\n\n") where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var rest = Substring(paragraph)
            while !rest.isEmpty {
                let piece = String(rest.prefix(maximum)); rest = rest.dropFirst(piece.count)
                if !current.isEmpty, current.count + piece.count + 2 > maximum { pages.append(current); current = "" }
                current += (current.isEmpty ? "" : "\n\n") + piece
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
