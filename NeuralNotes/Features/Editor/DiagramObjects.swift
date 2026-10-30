import UIKit
import NeuralNotesCore

@MainActor
enum DiagramObjects {
    private final class Entry {
        let height: Double, texts: [TextElement], images: [ImageElement], shapes: [ShapeElement]?, locks: [UUID]?
        let objects: [UUID: ConnectorObject]
        init(page: PageSnapshot, objects: [UUID: ConnectorObject]) {
            height = page.height; texts = page.texts; images = page.images; shapes = page.shapes; locks = page.lockedObjects; self.objects = objects
        }
        func matches(_ other: PageSnapshot) -> Bool {
            height == other.height && texts == other.texts && images == other.images && shapes == other.shapes && locks == other.lockedObjects
        }
    }
    private static let cache: NSCache<NSUUID, Entry> = {
        let value = NSCache<NSUUID, Entry>(); value.countLimit = 6; value.totalCostLimit = 16 * 1024 * 1024; return value
    }()
    static func make(_ page: PageSnapshot) -> [UUID: ConnectorObject] {
        if let found = cache.object(forKey: page.id as NSUUID), found.matches(page) { return found.objects }
        var rects: [UUID: SnapRect] = [:]
        for text in page.texts { rects[text.id] = SnapRect(RichText.bounds(text, pageHeight: page.height)) }
        let objects = page.connectorObjects(textRects: rects)
        var cost = objects.count * 512
        for text in page.texts { cost += text.text.utf8.count + (text.rtf?.count ?? 0) }
        for shape in page.shapes ?? [] { cost += (shape.label?.utf8.count ?? 0) + (shape.labelRTF?.count ?? 0) + (shape.vertices?.count ?? 0) * 32 }
        if cost <= 16 * 1024 * 1024 { cache.setObject(Entry(page: page, objects: objects), forKey: page.id as NSUUID, cost: cost) }
        return objects
    }
    static func clear() { cache.removeAllObjects() }
    static func textColor(_ page: PageSnapshot?) -> UIColor {
        page?.pdfFile == nil && page?.appearance?.tone == .slate ? .white : .black
    }
    static func paperColor(_ page: PageSnapshot?, shape: ShapeElement? = nil) -> UIColor {
        let rgb = page?.pdfFile == nil ? (page?.appearance?.tone ?? .white).rgb : (1.0, 1.0, 1.0)
        guard let fill = shape?.fill else { return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
        let alpha = shape?.fillOpacity ?? 0.25
        return UIColor(red: fill.red * alpha + rgb.0 * (1 - alpha), green: fill.green * alpha + rgb.1 * (1 - alpha), blue: fill.blue * alpha + rgb.2 * (1 - alpha), alpha: 1)
    }
    static func labelColor(_ shape: ShapeElement, page: PageSnapshot?) -> UIColor {
        guard let fill = shape.fill, (shape.fillOpacity ?? 0.25) > 0.7 else { return textColor(page) }
        let luminance = fill.red * 0.2126 + fill.green * 0.7152 + fill.blue * 0.0722
        return luminance < 0.45 ? .white : .black
    }
}

struct DiagramLabelLayout {
    var text: TextElement
    var value: NSAttributedString
    var box: CGRect
    var transform: CGAffineTransform
}
