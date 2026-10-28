import Foundation

public struct ShapeDragResult: Sendable {
    public var end: StrokeSample
    public var angleSnapped: Bool, proportionsSnapped: Bool
}
public enum ShapeSnapping {
    public static func drag(kind: ShapeKind, start: StrokeSample, end: StrokeSample) -> ShapeDragResult {
        if kind == .line || kind == .arrow || kind == .arc {
            let corrected = ShapeRecognizer.snappedEnd(start, end)
            let snapped = hypot(corrected.x - end.x, corrected.y - end.y) > 0.1
            return .init(end: corrected, angleSnapped: snapped, proportionsSnapped: false)
        }
        let dx = end.x - start.x, dy = end.y - start.y, width = abs(dx), height = abs(dy)
        if min(width, height) >= 8, kind == .polygon || kind == .star || max(width, height) / min(width, height) <= 1.1 {
            let side = max(width, height)
            let point = StrokeSample(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
            return .init(end: point, angleSnapped: false, proportionsSnapped: true)
        }
        return .init(end: end, angleSnapped: false, proportionsSnapped: false)
    }
}
