import Foundation

public enum MarkerInputMode: String, CaseIterable, Codable, Sendable {
    case words, freehand, rectangle
    public var title: String {
        switch self { case .words: return "Parole"; case .freehand: return "Tratto libero"; case .rectangle: return "Rettangolo" }
    }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .words }
}

public enum RectangularMarker {
    public static func make(_ rect: CGRect, color: InkColor) -> ShapeElement? {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite), rect.width >= 1, rect.height >= 1, color.isValid else { return nil }
        var value = ShapeElement(kind: .rectangle, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
            red: color.red, green: color.green, blue: color.blue, lineWidth: 1)
        value.rectangularMarker = true; value.fill = color; value.fillOpacity = 0.25; value.strokeOpacity = 0; value.cornerRadius = 0
        return value
    }
    /// Horizontal line runs, limited to the user's dragged rectangle. Independent
    /// columns/source groups are never joined across their empty space.
    public static func snapped(_ rect: CGRect, words: [PageWord]) -> [CGRect] {
        let eligible = words.filter { $0.rect.width > 0 && $0.rect.height > 0 && rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            .sorted { $0.rect.midY == $1.rect.midY ? $0.rect.minX < $1.rect.minX : $0.rect.midY < $1.rect.midY }
        var rows: [[CGRect]] = [], rowBounds: [CGRect] = []
        for word in eligible {
            if let last = rowBounds.last, abs(last.midY - word.rect.midY) <= min(last.height, word.rect.height) * 0.4 {
                rows[rows.count - 1].append(word.rect); rowBounds[rowBounds.count - 1] = last.union(word.rect)
            } else { rows.append([word.rect]); rowBounds.append(word.rect) }
        }
        var lines: [CGRect] = []
        for row in rows {
            var run: CGRect?
            for box in row.sorted(by: { $0.minX < $1.minX }) {
                if let current = run, box.minX - current.maxX <= max(12, box.height * 2) { run = current.union(box) }
                else { if let current = run { lines.append(current) }; run = box }
            }
            if let run { lines.append(run) }
        }
        return lines.map { $0.insetBy(dx: -1.5, dy: -1.5) }
    }
}
