import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A word of a page with its box in page coordinates. Lists of words keep the
/// reading order of their source: the PDF text layer, a typed box or the OCR.
public struct PageWord: Equatable, Sendable {
    public var text: String
    public var rect: CGRect
    /// Ends a line with a hyphen and goes on in the next word ("pro-" + "pria").
    public var hyphenated: Bool
    public init(text: String, rect: CGRect, hyphenated: Bool = false) {
        self.text = text; self.rect = rect; self.hyphenated = hyphenated
    }
}

/// Word geometry for the Lens: the word under a tap, the words a highlighter
/// stroke covers, the words inside a lasso, and every match of a search.
public enum PageWords {
    /// Words separated by spaces and line breaks, punctuation kept ("12-3", "critico?"),
    /// as UTF-16 ranges, the unit used by PDFKit and TextKit.
    public static func tokens(in text: String) -> [(range: NSRange, lineBreakBefore: Bool)] {
        let units = Array(text.utf16)
        var result: [(range: NSRange, lineBreakBefore: Bool)] = []
        var start: Int?, lineBreak = false
        for (index, unit) in units.enumerated() {
            if isSpace(unit) {
                if let first = start { result.append((NSRange(location: first, length: index - first), lineBreak)); start = nil; lineBreak = false }
                if isLineBreak(unit) { lineBreak = true }
            } else if start == nil { start = index }
        }
        if let first = start { result.append((NSRange(location: first, length: units.count - first), lineBreak)) }
        return result
    }

    /// A token that ends with a hyphen at the end of a line, followed by a lowercase word.
    public static func joinsNext(_ token: String, next: String, lineBreak: Bool) -> Bool {
        let hyphens: Set<Character> = ["-", "\u{2010}", "\u{00AD}"]
        guard lineBreak, token.count > 2, let last = token.last, hyphens.contains(last), let first = next.first else { return false }
        return first.isLowercase
    }

    /// The word under a point. An underline sits just below its words, so a point up
    /// to about one line below a word still selects it; a word hit directly wins.
    public static func word(at point: CGPoint, in words: [PageWord], tolerance: CGFloat = 4) -> Int? {
        var best: (index: Int, score: CGFloat)?
        for (index, word) in words.enumerated() {
            let box = word.rect
            guard !box.isNull, box.width > 0, box.height > 0,
                  point.x >= box.minX - tolerance, point.x <= box.maxX + tolerance else { continue }
            let score: CGFloat
            if point.y >= box.minY - tolerance / 2, point.y <= box.maxY + tolerance / 2 {
                // On the word: among overlapping slack, the closest center wins.
                score = abs(point.x - box.midX) / 1000 - 1000
            } else if point.y > box.maxY, point.y <= box.maxY + box.height * 1.1 {
                // Just below the word, where a pen underlines it.
                score = point.y - box.maxY
            } else { continue }
            if best == nil || score < best!.score { best = (index, score) }
        }
        return best?.index
    }

    /// The nearest word within a distance, for strokes that start or end between words.
    public static func nearest(to point: CGPoint, in words: [PageWord], within limit: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, word) in words.enumerated() where !word.rect.isNull {
            let dx = max(word.rect.minX - point.x, 0, point.x - word.rect.maxX)
            let dy = max(word.rect.minY - point.y, 0, point.y - word.rect.maxY)
            let distance = hypot(dx, dy)
            if distance <= limit, best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// The words a highlighter stroke covers, from its first to its last word in reading order.
    public static func range(from start: CGPoint, to end: CGPoint, in words: [PageWord], tolerance: CGFloat = 4) -> ClosedRange<Int>? {
        guard let first = word(at: start, in: words, tolerance: tolerance) ?? nearest(to: start, in: words, within: 24),
              let last = word(at: end, in: words, tolerance: tolerance) ?? nearest(to: end, in: words, within: 24) else { return nil }
        return min(first, last)...max(first, last)
    }

    /// What a Lens stroke selects. A flat stroke is a highlighter over whole words, from
    /// the first to the last; a closed loop taller than a line, or any stroke in area mode,
    /// takes the words inside it (an open drag in area mode: inside its rectangle).
    public static func pick(trace: [CGPoint], in words: [PageWord], area: Bool) -> [Int] {
        guard let first = trace.first, let last = trace.last, !words.isEmpty else { return [] }
        var box = CGRect(origin: first, size: .zero)
        for point in trace { box = box.union(CGRect(origin: point, size: .zero)) }
        let heights = words.map(\.rect.height).filter { $0 > 0 }.sorted()
        let line = heights.isEmpty ? 12 : heights[heights.count / 2]
        let closed = trace.count > 4 && hypot(last.x - first.x, last.y - first.y) < max(24, max(box.width, box.height) * 0.35)
        if area || (closed && box.height > line * 2) {
            return closed ? inside(polygon: trace, in: words) : inside(rect: box, in: words)
        }
        guard let range = range(from: first, to: last, in: words) else { return [] }
        return Array(range)
    }

    /// Whole words inside a lasso: a word counts when its center is inside the shape.
    public static func inside(polygon: [CGPoint], in words: [PageWord]) -> [Int] {
        guard polygon.count >= 3 else { return [] }
        return words.indices.filter { contains(polygon, CGPoint(x: words[$0].rect.midX, y: words[$0].rect.midY)) }
    }

    /// Whole words inside a rectangle: a word counts when its center is inside.
    public static func inside(rect: CGRect, in words: [PageWord]) -> [Int] {
        words.indices.filter { rect.contains(CGPoint(x: words[$0].rect.midX, y: words[$0].rect.midY)) }
    }

    /// The text of the chosen words: one space between words, hyphenated line ends joined again.
    public static func text(_ indices: [Int], in words: [PageWord]) -> String {
        let chosen = Array(Set(indices.filter { words.indices.contains($0) })).sorted()
        var result = ""
        for (position, index) in chosen.enumerated() {
            var piece = words[index].text
            let next = position + 1 < chosen.count ? chosen[position + 1] : nil
            if words[index].hyphenated, next == index + 1 { piece.removeLast(); result += piece; continue }
            result += piece
            if next != nil { result += " " }
        }
        return result
    }

    /// One highlight per line of the chosen words.
    public static func lineRects(_ indices: [Int], in words: [PageWord]) -> [CGRect] {
        var rects: [CGRect] = []
        var previous: CGRect?
        var previousIndex: Int?
        for index in Set(indices.filter({ words.indices.contains($0) })).sorted() {
            let box = words[index].rect
            if let last = previous, let current = rects.last, previousIndex == index - 1, sameLine(last, box) {
                rects[rects.count - 1] = current.union(box)
            } else { rects.append(box) }
            previous = box; previousIndex = index
        }
        return rects
    }

    /// Every occurrence of a query, ignoring case and accents, also across words:
    /// the indices of the words each occurrence touches.
    public static func matches(_ query: String, in words: [PageWord]) -> [[Int]] {
        let needle = Array(fold(query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")))
        guard !needle.isEmpty, !words.isEmpty else { return [] }
        var characters: [Character] = [], owners: [Int] = []
        for (index, word) in words.enumerated() {
            if index > 0 {
                let joined = words[index - 1].hyphenated
                if !joined { characters.append(" "); owners.append(index) }
            }
            var piece = word.text
            if word.hyphenated, index + 1 < words.count { piece.removeLast() }
            for character in fold(piece) { characters.append(character); owners.append(index) }
        }
        var found: [[Int]] = []
        var start = 0
        while start + needle.count <= characters.count {
            var equal = true
            for offset in needle.indices where characters[start + offset] != needle[offset] { equal = false; break }
            guard equal else { start += 1; continue }
            var touched: [Int] = []
            for position in start..<(start + needle.count) where characters[position] != " " || needle.count == 1 {
                if touched.last != owners[position] { touched.append(owners[position]) }
            }
            found.append(touched)
            start += needle.count
        }
        return found
    }

    static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midY - b.midY) < min(a.height, b.height) * 0.5
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }

    private static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let x = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || isLineBreak(unit) || (0x2000...0x200A).contains(unit) || unit == 0x202F || unit == 0x3000
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x0B || unit == 0x0C || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }
}
