import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum InkScratchEraser {
    static func erase(_ drawing: PKDrawing, in area: CGRect) -> (drawing: PKDrawing, erased: Bool) {
        var result: [PKStroke] = [], erased = false
        for stroke in drawing.strokes {
            guard stroke.renderBounds.intersects(area) else { result.append(stroke); continue }
            let transform = stroke.transform
            let determinant: CGFloat = transform.a * transform.d - transform.b * transform.c
            guard determinant.isFinite, abs(determinant) > 0.000001 else { result.append(stroke); continue }
            let scale: CGFloat = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
            let touchesInk = stroke.path.interpolatedPoints(by: .distance(2)).contains { point in
                let location = point.location.applying(transform)
                let expanded = area.insetBy(dx: -point.size.width * scale / 2, dy: -point.size.height * scale / 2)
                guard expanded.contains(location) else { return false }
                if let mask = stroke.mask {
                    return mask.cgPath.contains(point.location, using: mask.usesEvenOddFillRule ? .evenOdd : .winding)
                }
                return true
            }
            guard touchesInk else { result.append(stroke); continue }
            var inverse = transform.inverted()
            let localBounds = stroke.renderBounds.applying(inverse).insetBy(dx: -2, dy: -2)
            let base: CGPath
            if let mask = stroke.mask { base = mask.cgPath.normalized(using: mask.usesEvenOddFillRule ? .evenOdd : .winding) }
            else { base = CGPath(rect: localBounds, transform: nil) }
            let cut = CGPath(rect: area, transform: &inverse)
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
        let font = UIFont.systemFont(ofSize: CGFloat(text.fontSize))
        let storage = NSTextStorage(string: text.text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let size = CGSize(width: CGFloat(text.width), height: CGFloat(max(1, pageHeight - text.y)))
        let container = NSTextContainer(size: size); container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        let source = text.text as NSString
        var ranges: [NSRange] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byWords) { _, range, _, _ in
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: CGFloat(text.x), dy: CGFloat(text.y))
            if rect.intersects(area) { ranges.append(range) }
        }
        guard !ranges.isEmpty else { return text.text }
        let result = NSMutableString(string: text.text)
        for range in ranges.reversed() { result.deleteCharacters(in: range) }
        return (result as String).trimmingCharacters(in: .whitespaces)
    }
}
