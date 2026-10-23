import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum InkScratchEraser {
    static func erase(_ drawing: PKDrawing, in area: CGRect) -> (drawing: PKDrawing, erased: Bool) {
        erase(drawing, in: CGPath(rect: area, transform: nil))
    }

    static func coverage(of scratch: PKStroke) -> CGPath {
        let trace = CGMutablePath()
        var started = false
        var width: CGFloat = 3
        let scale = max(hypot(scratch.transform.a, scratch.transform.b), hypot(scratch.transform.c, scratch.transform.d))
        for point in scratch.path.interpolatedPoints(by: .distance(2)) {
            let location = point.location.applying(scratch.transform)
            if started { trace.addLine(to: location) } else { trace.move(to: location); started = true }
            width = max(width, point.size.width * scale)
        }
        // A narrow round eraser follows the actual scribble. Never fill its
        // bounding box or its closed interior: nearby ink must remain intact.
        return trace.copy(strokingWithWidth: min(20, width + 6), lineCap: .round, lineJoin: .round, miterLimit: 1)
            .normalized(using: .winding)
    }

    static func erase(_ drawing: PKDrawing, in area: CGPath, wholeStroke: Bool = false) -> (drawing: PKDrawing, erased: Bool) {
        var result: [PKStroke] = [], erased = false
        for stroke in drawing.strokes {
            guard stroke.renderBounds.intersects(area.boundingBoxOfPath) else { result.append(stroke); continue }
            let transform = stroke.transform
            let determinant: CGFloat = transform.a * transform.d - transform.b * transform.c
            guard determinant.isFinite, abs(determinant) > 0.000001 else { result.append(stroke); continue }
            let scale: CGFloat = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
            let trace = CGMutablePath()
            var started = false, width: CGFloat = 0.1
            var first: CGPoint?, hasLength = false
            for point in stroke.path.interpolatedPoints(by: .distance(2)) {
                let location = point.location.applying(transform)
                if started { trace.addLine(to: location) } else { trace.move(to: location); started = true }
                if let first { hasLength = hasLength || hypot(location.x - first.x, location.y - first.y) > 0.01 }
                else { first = location }
                width = max(width, max(point.size.width, point.size.height) * scale)
            }
            var visible = trace.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
            if !hasLength, let first {
                visible = CGPath(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width), transform: nil)
            }
            if let mask = stroke.mask {
                var world = transform
                if let clipped = mask.cgPath.normalized(using: mask.usesEvenOddFillRule ? .evenOdd : .winding).copy(using: &world) {
                    visible = visible.intersection(clipped, using: .winding)
                }
            }
            guard !visible.intersection(area, using: .winding).isEmpty else { result.append(stroke); continue }
            // Scribbling uses stroke erasure: remove the entire crossed stroke,
            // including disconnected visible pieces left by an earlier pixel erasure.
            // Test the visible outline first so an erased gap or enclosed empty area
            // cannot delete ink that the scribble never actually touched.
            if wholeStroke { erased = true; continue }
            var inverse = transform.inverted()
            let localBounds = stroke.renderBounds.applying(inverse).insetBy(dx: -2, dy: -2)
            let base: CGPath
            if let mask = stroke.mask { base = mask.cgPath.normalized(using: mask.usesEvenOddFillRule ? .evenOdd : .winding) }
            else { base = CGPath(rect: localBounds, transform: nil) }
            guard let cut = area.copy(using: &inverse) else { result.append(stroke); continue }
            let remaining = base.subtracting(cut, using: .winding)
            erased = true
            if !remaining.isEmpty {
                result.append(PKStroke(ink: stroke.ink, path: stroke.path, transform: transform, mask: UIBezierPath(cgPath: remaining)))
            }
        }
        return (PKDrawing(strokes: result), erased)
    }
}

@MainActor
enum TextScratchEraser {
    static func eraseWords(_ text: TextElement, in area: CGRect, pageHeight: Double) -> String {
        eraseWords(text, in: CGPath(rect: area, transform: nil), pageHeight: pageHeight)
    }
    static func eraseWords(_ text: TextElement, in area: CGPath, pageHeight: Double) -> String {
        eraseFormattedWords(text, in: area, pageHeight: pageHeight).text
    }
    static func eraseFormattedWords(_ text: TextElement, in area: CGPath, pageHeight: Double) -> TextElement {
        var inverse = RichText.rotation(text, pageHeight: pageHeight).inverted()
        let erasure = area.copy(using: &inverse) ?? area
        let storage = NSTextStorage(attributedString: RichText.attributed(text))
        let layout = NSLayoutManager()
        let size = CGSize(width: CGFloat(text.width), height: CGFloat(max(1, pageHeight - text.y)))
        let container = NSTextContainer(size: size); container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        let source = text.text as NSString
        var ranges: [NSRange] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byWords) { _, range, _, _ in
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: CGFloat(text.x), dy: CGFloat(text.y))
            guard rect.intersects(erasure.boundingBoxOfPath), rect.width > 0, rect.height > 0 else { return }
            let columns = min(40, max(3, Int(ceil(rect.width / 4))))
            let rows = min(12, max(3, Int(ceil(rect.height / 4))))
            var covered = 0
            for x in 0..<columns {
                for y in 0..<rows {
                    let px = rect.minX + (CGFloat(x) + 0.5) * rect.width / CGFloat(columns)
                    let py = rect.minY + (CGFloat(y) + 0.5) * rect.height / CGFloat(rows)
                    if erasure.contains(CGPoint(x: px, y: py)) { covered += 1 }
                }
            }
            if covered * 2 >= columns * rows { ranges.append(range) }
        }
        guard !ranges.isEmpty else { return text }
        let result = NSMutableAttributedString(attributedString: storage)
        for range in ranges.reversed() { result.deleteCharacters(in: range) }
        let trimmed = result.string.trimmingCharacters(in: .whitespaces)
        let kept = (result.string as NSString).range(of: trimmed)
        let attributed = trimmed.isEmpty ? NSAttributedString(string: "") : result.attributedSubstring(from: kept)
        var updated = text; updated.text = attributed.string; updated.rtf = RichText.data(attributed)
        return updated
    }
}
