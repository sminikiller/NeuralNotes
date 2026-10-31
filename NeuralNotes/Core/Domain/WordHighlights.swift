import Foundation

/// Word marks are vector rectangles, not simulated marker strokes. The native
/// ink stays unchanged; repeated passes over a word do not darken its color.
public enum WordHighlights {
    public enum Failure: LocalizedError {
        case limit
        public var errorDescription: String? { "Troppe evidenziazioni in questa pagina. Rimuovine alcune prima di aggiungerne altre." }
    }
    private struct Key: Hashable {
        let x: Double, y: Double, width: Double, height: Double
        let color: InkColor
        let opacity: Double
        init(_ mark: PDFMarkup) {
            x = mark.x; y = mark.y; width = mark.width; height = mark.height
            color = mark.color ?? .yellow; opacity = mark.opacity ?? 0.25
        }
    }
    public static func appending(words: [PageWord], indices: [Int], to existing: [PDFMarkup],
                                 color: InkColor, width: Double, height: Double) throws -> [PDFMarkup] {
        guard color.isValid, width.isFinite, height.isFinite, width > 0, height > 0 else { return existing }
        var result = existing
        var seen = Set(existing.filter { $0.wordHighlight == true }.map(Key.init))
        var ids = Set(existing.map(\.id))
        let page = CGRect(x: 0, y: 0, width: width, height: height)
        for i in Set(indices).sorted() where words.indices.contains(i) {
            let raw = words[i].rect
            guard [raw.minX, raw.minY, raw.width, raw.height].allSatisfy(\.isFinite), raw.width > 0, raw.height > 0 else { continue }
            let rect = raw.insetBy(dx: -1.5, dy: -1.5).intersection(page)
            guard !rect.isNull, !rect.isEmpty, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { continue }
            var mark = PDFMarkup(kind: .highlight, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, text: words[i].text)
            mark.wordHighlight = true; mark.color = color; mark.opacity = 0.25
            guard seen.insert(Key(mark)).inserted else { continue }
            guard result.count < 20_000 else { throw Failure.limit }
            while ids.contains(mark.id) { mark.id = UUID() }
            ids.insert(mark.id); result.append(mark)
        }
        return result
    }
}
