import Foundation

/// The light formatting the Lens asks the model for: short paragraphs, lists with
/// "- " or "1. ", **bold** key terms and *italic*. Anything else stays plain text,
/// so an answer is never lost because of a stray marker.
public enum LensMarkup {
    public struct Span: Equatable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public init(text: String, bold: Bool = false, italic: Bool = false) { self.text = text; self.bold = bold; self.italic = italic }
    }

    public enum Block: Equatable, Sendable {
        case paragraph([Span])
        case bullet([Span])
        /// A step of an ordered list, with its marker ("1.").
        case numbered(String, [Span])
        case heading([Span])
    }

    public static func blocks(_ text: String) -> [Block] {
        var result: [Block] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let rest = bulletText(line) { result.append(.bullet(spans(rest))) }
            else if let step = numbered(line) { result.append(.numbered(step.marker, spans(step.rest))) }
            else if line.hasPrefix("#") { result.append(.heading(spans(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))) }
            else { result.append(.paragraph(spans(line))) }
        }
        return result
    }

    /// Plain text for copies and for the note's own text: bullets as "• ", no markers.
    public static func plain(_ text: String) -> String {
        blocks(text).map { block -> String in
            switch block {
            case .paragraph(let spans), .heading(let spans): return joined(spans)
            case .bullet(let spans): return "• " + joined(spans)
            case .numbered(let marker, let spans): return marker + " " + joined(spans)
            }
        }.joined(separator: "\n")
    }

    public static func joined(_ spans: [Span]) -> String { spans.map(\.text).joined() }

    /// **bold** and *italic* inside a line; unpaired markers are kept as written.
    public static func spans(_ line: String) -> [Span] {
        var result: [Span] = []
        func add(_ text: String, bold: Bool, italic: Bool) {
            guard !text.isEmpty else { return }
            if let last = result.last, last.bold == bold, last.italic == italic { result[result.count - 1].text += text }
            else { result.append(Span(text: text, bold: bold, italic: italic)) }
        }
        let boldParts = line.components(separatedBy: "**")
        let paired = boldParts.count % 2 == 1
        for (index, part) in boldParts.enumerated() {
            let bold = paired && index % 2 == 1
            if !paired && index > 0 { add("**", bold: false, italic: false) }
            let italicParts = part.components(separatedBy: "*")
            let italicPaired = italicParts.count % 2 == 1
            for (position, segment) in italicParts.enumerated() {
                if !italicPaired && position > 0 { add("*", bold: bold, italic: false) }
                add(segment, bold: bold, italic: italicPaired && position % 2 == 1)
            }
        }
        return result
    }

    private static func bulletText(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• ", "•\t", "– ", "· "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numbered(_ line: String) -> (marker: String, rest: String)? {
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...3).contains(digits.count) else { return nil }
        let after = line.dropFirst(digits.count)
        guard let mark = after.first, mark == "." || mark == ")", let gap = after.dropFirst().first, gap == " " || gap == "\t" else { return nil }
        return (String(digits) + ".", String(after.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}
