import UIKit
import CoreText

/// Opacity probes replay drawing commands. Only their final Screen pass emits
/// searchable glyphs; coefficient passes paint the same glyph outlines. The
/// nesting counters preserve that rule through merged composition trees.
@MainActor enum LayerPDFText {
    private static var layoutDepth = 0
    private static var outlineDepth = 0
    static func layout(_ enabled: Bool, _ body: () -> Void) {
        if enabled { layoutDepth += 1 }; defer { if enabled { layoutDepth -= 1 } }
        body()
    }
    static func outlines(_ enabled: Bool, _ body: () -> Void) {
        if enabled { outlineDepth += 1 }; defer { if enabled { outlineDepth -= 1 } }
        body()
    }
    static func draw(_ value: NSAttributedString, in box: CGRect, context: CGContext) {
        guard layoutDepth > 0 else { value.draw(in: box); return }
        let storage = NSTextStorage(attributedString: value)
        let manager = GlyphLayout(); manager.outlinesOnly = outlineDepth > 0
        let container = NSTextContainer(size: box.size); container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: box.origin)
        manager.drawGlyphs(forGlyphRange: range, at: box.origin)
    }

    private final class GlyphLayout: NSLayoutManager {
        var outlinesOnly = false
        override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>,
                                  count glyphCount: Int, font: UIFont, textMatrix: CGAffineTransform,
                                  attributes: [NSAttributedString.Key: Any] = [:], in context: CGContext) {
            let native = font as CTFont
            if CTFontGetSymbolicTraits(native).contains(.traitColorGlyphs) {
                super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font,
                    textMatrix: textMatrix, attributes: attributes, in: context); return
            }
            // Preserve the resolved font instance, including optical-size and
            // variation axes. Recreating a system font by name can change its
            // glyph outlines while the layout still uses the original metrics.
            context.saveGState(); defer { context.restoreGState() }
            if !outlinesOnly {
                // Emit selectable glyphs exactly once, without painting them.
                // Both coefficient and final passes paint identical contours;
                // font raster hinting must not change their blend equations.
                context.saveGState()
                context.setFont(CTFontCopyGraphicsFont(native, nil)); context.setFontSize(font.pointSize)
                context.textMatrix = textMatrix; context.setTextDrawingMode(.invisible)
                context.showGlyphs(Array(UnsafeBufferPointer(start: glyphs, count: glyphCount)),
                    at: Array(UnsafeBufferPointer(start: positions, count: glyphCount)))
                context.restoreGState()
            }
            if let color = attributes[.foregroundColor] as? UIColor { context.setFillColor(color.cgColor) }
            if let color = attributes[.strokeColor] as? UIColor { context.setStrokeColor(color.cgColor) }
            let stroke = (attributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0
            if stroke != 0 { context.setLineWidth(font.pointSize * CGFloat(abs(stroke)) / 100) }
            for index in 0..<glyphCount {
                if let path = CTFontCreatePathForGlyph(native, glyphs[index], nil) {
                    var transform = textMatrix
                    transform.tx = positions[index].x; transform.ty = positions[index].y
                    if let positioned = path.copy(using: &transform) {
                        context.addPath(positioned)
                        context.drawPath(using: stroke == 0 ? .fill : stroke < 0 ? .fillStroke : .stroke)
                    }
                }
            }
        }
    }
}
