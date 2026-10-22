import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum LensGeometry {
    /// A circle ends near its starting point: use the whole path instead of
    /// collapsing it into the rectangle between just its two endpoints.
    public static func selection(trace: [StrokeSample], pageWidth: Double, pageHeight: Double) -> CGRect? {
        guard !trace.isEmpty, trace.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              pageWidth.isFinite, pageHeight.isFinite, pageWidth > 0, pageHeight > 0 else { return nil }
        var minX = trace[0].x, maxX = minX, minY = trace[0].y, maxY = minY
        for point in trace.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return selection(from: StrokeSample(x: minX, y: minY), to: StrokeSample(x: maxX, y: maxY), pageWidth: pageWidth, pageHeight: pageHeight)
    }
    /// In the explicit Lens tool a shallow horizontal drag selects the text
    /// above an underline. Ordinary pen/highlighter strokes are unaffected.
    public static func selection(from start: StrokeSample, to end: StrokeSample, pageWidth: Double, pageHeight: Double) -> CGRect? {
        guard [start.x, start.y, end.x, end.y, pageWidth, pageHeight].allSatisfy(\.isFinite), pageWidth > 0, pageHeight > 0 else { return nil }
        let x = CGFloat(min(start.x, end.x)), y = CGFloat(min(start.y, end.y))
        let width = CGFloat(abs(end.x - start.x)), height = CGFloat(abs(end.y - start.y))
        var box = CGRect(x: x, y: y, width: width, height: height)
        if box.width >= 12, box.height <= 12 {
            let above: CGFloat = min(80, max(32, box.width * 0.2))
            box = CGRect(x: box.minX - 4, y: box.minY - above, width: box.width + 8, height: box.height + above + 8)
        }
        let page = CGRect(x: CGFloat.zero, y: CGFloat.zero, width: CGFloat(pageWidth), height: CGFloat(pageHeight))
        box = box.intersection(page)
        return box.isNull || box.width <= 3 || box.height <= 3 ? nil : box
    }
}

public extension LensGeometry {
    /// Approximate size of a typed answer: enough to keep it clear of other notes.
    static func answerSize(text: String, fontSize: Double, width: Double) -> CGSize {
        let size = max(8, fontSize.isFinite ? fontSize : 16), lineWidth = max(80, width.isFinite ? width : 360)
        let perLine = max(10, Int(lineWidth / (size * 0.52)))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
        return CGSize(width: lineWidth, height: Double(max(1, lines)) * size * 1.35 + 16)
    }

    /// Where an inserted answer goes: beside the selection when there is one,
    /// otherwise in the first free band of the page. It never leaves the page and
    /// never covers the selection; other notes are avoided whenever possible.
    static func placement(text: String, near anchor: CGRect?, occupied: [CGRect], pageWidth: Double, pageHeight: Double, fontSize: Double = 16, maximumWidth: CGFloat = 360) -> CGRect {
        let margin: CGFloat = 24
        let pageW = CGFloat(pageWidth.isFinite && pageWidth > 0 ? pageWidth : 768), pageH = CGFloat(pageHeight.isFinite && pageHeight > 0 ? pageHeight : 1024)
        let width = max(80, min(maximumWidth.isFinite ? maximumWidth : 360, pageW - 2 * margin))
        let height = min(answerSize(text: text, fontSize: fontSize, width: Double(width)).height, max(40, pageH - 2 * margin))
        let page = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let others = occupied.filter { !$0.isNull && $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite }
        func clamped(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: min(max(margin, x), max(margin, pageW - width - margin)), y: min(max(margin, y), max(margin, pageH - height - margin)), width: width, height: height)
        }
        func free(_ rect: CGRect) -> Bool { !others.contains(where: { $0.intersects(rect) }) }
        if let anchor, !anchor.isNull, anchor.minX.isFinite, anchor.minY.isFinite, anchor.width.isFinite, anchor.height.isFinite {
            let box = anchor.intersection(page).isNull ? anchor : anchor.intersection(page)
            let candidates = [clamped(box.maxX + 16, box.minY), clamped(box.minX, box.maxY + 12),
                              clamped(box.minX - width - 16, box.minY), clamped(box.minX, box.minY - height - 12)]
            let beside = candidates.filter { !$0.intersects(box) }
            if let found = beside.first(where: free) { return found }
            // Further down, aligned with the selection, before covering anything else.
            var y = box.maxY + 12
            while y + height + margin <= pageH {
                let rect = clamped(box.minX, y)
                if !rect.intersects(box), free(rect) { return rect }
                y += 24
            }
            return beside.first ?? clamped(box.minX, box.maxY + 12)
        }
        var y: CGFloat = 64
        while y + height + margin <= pageH {
            let rect = clamped(48, y)
            if free(rect) { return rect }
            y += 24
        }
        return clamped(48, 64)
    }
}
