import UIKit
import NeuralNotesCore

@MainActor
extension RichText {
    static func scaled(_ source: TextElement, by factor: Double) -> TextElement {
        guard factor.isFinite, factor > 0 else { return source }
        let scale = CGFloat(factor)
        var result = source
        result.width = max(1, min(20000, source.width * factor))
        result.fontSize = min(1000, max(1, source.fontSize * factor))
        let value = NSMutableAttributedString(attributedString: attributed(source))
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            if let font = attributes[.font] as? UIFont {
                value.addAttribute(.font, value: font.withSize(min(1000, max(1, font.pointSize * scale))), range: range)
            }
            for key in [NSAttributedString.Key.baselineOffset, .kern] {
                if let number = attributes[key] as? NSNumber { value.addAttribute(key, value: number.doubleValue * factor, range: range) }
            }
            if let original = attributes[.paragraphStyle] as? NSParagraphStyle,
               let style = original.mutableCopy() as? NSMutableParagraphStyle {
                style.lineSpacing *= scale; style.paragraphSpacing *= scale; style.paragraphSpacingBefore *= scale
                style.firstLineHeadIndent *= scale; style.headIndent *= scale; style.tailIndent *= scale
                style.minimumLineHeight *= scale; style.maximumLineHeight *= scale
                style.defaultTabInterval *= scale
                style.tabStops = original.tabStops.map { NSTextTab(textAlignment: $0.alignment, location: $0.location * scale, options: $0.options) }
                value.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        result.rtf = data(value); return result
    }
    static func fittingHeight(_ source: TextElement, height: Double, pageHeight: Double) -> TextElement {
        let original = bounds(source, pageHeight: pageHeight).height
        guard original > 0, height.isFinite, height > 0 else { return source }
        var factor = height / original, result = source
        // Text bounds include fixed minimum padding and optical font metrics;
        // multiplying font size by a box ratio alone is not sufficient.
        for _ in 0..<5 {
            result = scaled(source, by: factor)
            let actual = bounds(result, pageHeight: pageHeight).height
            if abs(actual - height) < 0.05 || actual <= 0 { break }
            factor *= height / actual
        }
        return result
    }
}
