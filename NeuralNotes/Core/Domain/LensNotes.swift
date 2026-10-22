import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The text a Lens note explains: its page and the underlined or circled area.
public struct LensNoteSource: Codable, Equatable, Sendable {
    public var pageID: UUID
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(pageID: UUID, rect: CGRect) {
        self.pageID = pageID
        x = Double(rect.minX); y = Double(rect.minY); width = Double(rect.width); height = Double(rect.height)
    }
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width >= 0 && height >= 0 }
}

/// A note written by the Lens AI. It stays an ordinary text box (move, resize,
/// edit, export) and also remembers its title, its origin line, the text it
/// explains and whether it is reduced to an icon on the page.
public struct LensNoteInfo: Codable, Equatable, Sendable {
    public var title: String
    public var origin: String?
    public var source: LensNoteSource?
    public var collapsed: Bool?
    public var createdAt: Double?
    public init(title: String, origin: String? = nil, source: LensNoteSource? = nil, collapsed: Bool = false, createdAt: Double? = nil) {
        self.title = String(title.prefix(LensNotes.titleLimit)); self.origin = origin.map { String($0.prefix(LensNotes.titleLimit)) }
        self.source = source; self.collapsed = collapsed ? true : nil; self.createdAt = createdAt
    }
    public var isCollapsed: Bool { collapsed == true }
    public var isValid: Bool {
        title.count <= LensNotes.titleLimit && (origin?.count ?? 0) <= LensNotes.titleLimit
            && source?.isValid != false && createdAt?.isFinite != false
    }
}

/// One row of the notes list: where the note is and what it says.
public struct IndexedLensNote: Identifiable, Equatable, Sendable {
    public var id: UUID { textID }
    public let pageID: UUID
    public let pageNumber: Int
    public let textID: UUID
    public let title: String
    public let body: String
    public let collapsed: Bool
    public let hasSource: Bool
}

public enum LensNotes {
    public static let titleLimit = 400
    /// Side of the icon that stands for a reduced note.
    public static let badgeSize = 30.0

    /// Every Lens note of the notebook, page by page and top to bottom.
    public static func index(_ pages: [PageSnapshot]) -> [IndexedLensNote] {
        var result: [IndexedLensNote] = []
        for (offset, page) in pages.enumerated() {
            let notes = page.texts.filter { $0.lensNote != nil }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            for text in notes {
                guard let note = text.lensNote else { continue }
                let title = note.title.isEmpty ? TermExplanationRequest.line(text.text, limit: 80) : note.title
                result.append(IndexedLensNote(pageID: page.id, pageNumber: offset + 1, textID: text.id, title: title,
                                              body: body(of: text), collapsed: note.isCollapsed, hasSource: note.source != nil))
            }
        }
        return result
    }

    /// The part of a note the student edits: its text without the title line and the origin line.
    public static func body(of text: TextElement) -> String {
        var lines = text.text.components(separatedBy: "\n")
        if let title = text.lensNote?.title, let first = lines.first,
           first.trimmingCharacters(in: .whitespaces) == title.trimmingCharacters(in: .whitespaces) { lines.removeFirst() }
        if let origin = text.lensNote?.origin, !origin.isEmpty, let last = lines.last, last == origin { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The plain text of a note: title, body and origin, one per paragraph.
    public static func text(title: String, body: String, origin: String?) -> String {
        [title, body, origin ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public extension LensNotes {
    /// The icon of a reduced note, at the note's top-left corner.
    static func badge(x: Double, y: Double) -> CGRect {
        CGRect(x: x, y: y, width: badgeSize, height: badgeSize)
    }

    /// The round control that reduces an open note, on its top-right corner and inside the page.
    static func reduceControl(note box: CGRect, pageWidth: Double, pageHeight: Double) -> CGRect {
        let side: CGFloat = 24
        let x = min(max(0, box.maxX + 8 - side / 2), max(0, CGFloat(pageWidth) - side))
        let y = min(max(0, box.minY - 8 - side / 2), max(0, CGFloat(pageHeight) - side))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// A line from the note to the text it explains, only when the two are apart.
    static func connector(note: CGRect, source: CGRect) -> (from: CGPoint, to: CGPoint)? {
        guard !note.isNull, !source.isNull, !note.isEmpty, !source.isEmpty,
              !note.insetBy(dx: -12, dy: -12).intersects(source) else { return nil }
        let from = closest(on: note.insetBy(dx: -8, dy: -8), to: CGPoint(x: source.midX, y: source.midY))
        return (from, closest(on: source, to: from))
    }

    /// Where an opened note fits on the page, starting from the place of its icon.
    static func opened(_ box: CGRect, pageWidth: Double, pageHeight: Double) -> CGPoint {
        let margin: CGFloat = 8
        let x = max(margin, min(box.minX, CGFloat(pageWidth) - box.width - margin))
        let y = max(margin, min(box.minY, CGFloat(pageHeight) - box.height - margin))
        return CGPoint(x: x, y: y)
    }

    /// A free spot for a note icon next to its text: right, left, below, above;
    /// without a free spot the icon goes right of the text anyway.
    static func badgePlacement(near anchor: CGRect?, occupied: [CGRect], pageWidth: Double, pageHeight: Double) -> CGRect {
        let side = CGFloat(badgeSize), gap: CGFloat = 6
        let pageW = CGFloat(pageWidth.isFinite && pageWidth > 0 ? pageWidth : 768), pageH = CGFloat(pageHeight.isFinite && pageHeight > 0 ? pageHeight : 1024)
        func clamped(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: min(max(4, x), max(4, pageW - side - 4)), y: min(max(4, y), max(4, pageH - side - 4)), width: side, height: side)
        }
        let others = occupied.filter { !$0.isNull && $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite }
        func free(_ rect: CGRect) -> Bool { !others.contains(where: { $0.intersects(rect) }) }
        guard let anchor, !anchor.isNull, anchor.minX.isFinite, anchor.minY.isFinite, anchor.width.isFinite, anchor.height.isFinite else {
            var y: CGFloat = 24
            while y + side < pageH { let rect = clamped(pageW - side - 12, y); if free(rect) { return rect }; y += side + gap }
            return clamped(pageW - side - 12, 24)
        }
        let candidates = [clamped(anchor.maxX + gap, anchor.minY), clamped(anchor.minX - side - gap, anchor.minY),
                          clamped(anchor.maxX - side, anchor.maxY + gap), clamped(anchor.maxX - side, anchor.minY - side - gap)]
        return candidates.first(where: { free($0) && !$0.intersects(anchor) }) ?? candidates[0]
    }

    private static func closest(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }
}
