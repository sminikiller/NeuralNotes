import UIKit
import NeuralNotesCore

@MainActor
enum DiagramLabels {
    private final class Entry {
        let source: ShapeElement, color: UIColor, layout: DiagramLabelLayout
        init(_ source: ShapeElement, color: UIColor, layout: DiagramLabelLayout) { self.source = source; self.color = color; self.layout = layout }
    }
    private static let cache: NSCache<NSUUID, Entry> = {
        let value = NSCache<NSUUID, Entry>(); value.countLimit = 256; value.totalCostLimit = 8 * 1024 * 1024; return value
    }()
    private final class EdgeEntry {
        let text: String, rtf: Data?, fontSize: Double, color: UIColor, layout: DiagramLabelLayout
        init(text: String, rtf: Data?, fontSize: Double, color: UIColor, layout: DiagramLabelLayout) {
            self.text = text; self.rtf = rtf; self.fontSize = fontSize; self.color = color; self.layout = layout
        }
    }
    private static let edgeCache: NSCache<NSUUID, EdgeEntry> = {
        let value = NSCache<NSUUID, EdgeEntry>(); value.countLimit = 256; value.totalCostLimit = 8 * 1024 * 1024; return value
    }()
    static func clear() { cache.removeAllObjects(); edgeCache.removeAllObjects() }
    static func shape(_ shape: ShapeElement, page: PageSnapshot?) -> DiagramLabelLayout? {
        guard let label = shape.label, !label.isEmpty else { return nil }
        var source = shape; source.x = 0; source.y = 0; source.rotation = nil; source.audioAnchor = nil; source.pageLink = nil
        let color = DiagramObjects.labelColor(shape, page: page)
        let local: DiagramLabelLayout
        if let found = cache.object(forKey: shape.id as NSUUID), found.source == source, found.color.isEqual(color) { local = found.layout }
        else {
            let region = ShapeLabelRegion.rect(source).cgRect
            let made = layout(id: shape.id, text: label, rtf: shape.labelRTF, fontSize: shape.labelFontSize ?? 18,
                              region: region, color: color, autoFit: shape.labelAutoFit ?? true)
            cache.setObject(Entry(source, color: color, layout: made), forKey: shape.id as NSUUID, cost: (shape.labelRTF?.count ?? 0) + label.utf8.count * 4)
            local = made
        }
        var result = local; result.box = local.box.offsetBy(dx: shape.x, dy: shape.y)
        result.text.x += shape.x; result.text.y += shape.y
        let cx = shape.x + shape.width / 2, cy = shape.y + shape.height / 2
        result.transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: (shape.rotation ?? 0) * .pi / 180).translatedBy(x: -cx, y: -cy)
        return result
    }
    static func connector(_ connector: ConnectorElement, objects: [UUID: ConnectorObject], page: PageSnapshot?) -> DiagramLabelLayout? {
        guard let label = connector.label, !label.isEmpty else { return nil }
        let color = DiagramObjects.textColor(page), fontSize = connector.labelFontSize ?? 16
        let local: DiagramLabelLayout
        if let found = edgeCache.object(forKey: connector.id as NSUUID), found.text == label, found.rtf == connector.labelRTF, found.fontSize == fontSize, found.color.isEqual(color) { local = found.layout }
        else {
            var proxy = TextElement(text: label); proxy.id = connector.id; proxy.rtf = connector.labelRTF; proxy.fontSize = fontSize
            let natural = label.count < 1000 ? RichText.attributed(proxy, color: color).size().width + 8 : 240
            let width = min(240, max(40, ceil(natural)))
            local = layout(id: connector.id, text: label, rtf: connector.labelRTF, fontSize: fontSize,
                           region: CGRect(x: -width / 2, y: -100, width: width, height: 200), color: color, autoFit: true)
            edgeCache.setObject(EdgeEntry(text: label, rtf: connector.labelRTF, fontSize: fontSize, color: color, layout: local),
                                forKey: connector.id as NSUUID, cost: (connector.labelRTF?.count ?? 0) + label.utf8.count * 4)
        }
        let point = ConnectorGeometry.midpoint(connector, objects: objects)
        var result = local; result.box = local.box.offsetBy(dx: point.x, dy: point.y)
        result.text.x += point.x; result.text.y += point.y; return result
    }
    private static func layout(id: UUID, text: String, rtf: Data?, fontSize: Double, region: CGRect, color: UIColor, autoFit: Bool) -> DiagramLabelLayout {
        var proxy = TextElement(text: text); proxy.id = id; proxy.fontSize = fontSize; proxy.rtf = rtf; proxy.width = max(1, region.width)
        let value = NSMutableAttributedString(attributedString: RichText.attributed(proxy, color: color))
        let range = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.paragraphStyle, in: range) { item, subrange, _ in
            let paragraph = (item as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.alignment = .center; value.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
        }
        func measured() -> CGFloat {
            ceil(value.boundingRect(with: CGSize(width: max(1, region.width), height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        }
        var height = measured(), effectiveFont = fontSize
        if autoFit {
            for _ in 0..<8 where height > region.height {
                let ratio = min(0.95, region.height / max(1, height))
                var changed = false
                value.enumerateAttribute(.font, in: range) { item, subrange, _ in
                    let font = item as? UIFont ?? UIFont.systemFont(ofSize: fontSize)
                    let size = max(6, min(200, font.pointSize * ratio))
                    if size < font.pointSize - 0.01 { changed = true }
                    value.addAttribute(.font, value: font.withSize(size), range: subrange)
                }
                value.enumerateAttribute(.paragraphStyle, in: range) { item, subrange, _ in
                    guard let paragraph = (item as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
                    paragraph.firstLineHeadIndent *= ratio; paragraph.headIndent *= ratio; paragraph.tailIndent *= ratio
                    paragraph.lineSpacing *= ratio; paragraph.paragraphSpacing *= ratio; paragraph.paragraphSpacingBefore *= ratio
                    paragraph.minimumLineHeight *= ratio; paragraph.maximumLineHeight *= ratio
                    paragraph.tabStops = paragraph.tabStops.map { NSTextTab(textAlignment: $0.alignment, location: $0.location * ratio, options: $0.options) }
                    value.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
                }
                for key in [NSAttributedString.Key.baselineOffset, .kern] {
                    value.enumerateAttribute(key, in: range) { item, subrange, _ in
                        if let number = item as? NSNumber { value.addAttribute(key, value: number.doubleValue * ratio, range: subrange) }
                    }
                }
                effectiveFont = max(6, effectiveFont * ratio)
                let next = measured(); height = next
                if !changed { break }
            }
        }
        height = min(region.height, max(effectiveFont + 4, height))
        let box = CGRect(x: region.minX, y: region.midY - height / 2, width: region.width, height: height)
        proxy.x = box.minX; proxy.y = box.minY; proxy.fontSize = effectiveFont; proxy.rtf = RichText.data(value)
        return .init(text: proxy, value: value, box: box, transform: .identity)
    }
    static func draw(_ layout: DiagramLabelLayout, context: CGContext) {
        context.saveGState(); context.concatenate(layout.transform); layout.value.draw(in: layout.box); context.restoreGState()
    }
}
