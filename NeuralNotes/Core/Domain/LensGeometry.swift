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
