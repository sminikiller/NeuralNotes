import UIKit
import NeuralNotesCore

@MainActor
enum DiagramObjects {
    private final class Entry {
        let page: PageSnapshot, objects: [UUID: ConnectorObject]
        init(page: PageSnapshot, objects: [UUID: ConnectorObject]) { self.page = page; self.objects = objects }
        func matches(_ other: PageSnapshot) -> Bool {
            page.height == other.height && page.texts == other.texts && page.images == other.images && page.shapes == other.shapes && page.lockedObjects == other.lockedObjects
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
        cache.setObject(Entry(page: page, objects: objects), forKey: page.id as NSUUID, cost: objects.count * 512)
        return objects
    }
    static func textColor(_ page: PageSnapshot?) -> UIColor {
        page?.pdfFile == nil && page?.appearance?.tone == .slate ? .white : .black
    }
}

struct DiagramLabelLayout {
    var text: TextElement
    var value: NSAttributedString
    var box: CGRect
    var transform: CGAffineTransform
}
