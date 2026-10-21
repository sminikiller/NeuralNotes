import Foundation

public enum PreciseLine {
    public static func snappedEnd(from start: StrokeSample, to end: StrokeSample, toleranceDegrees: Double = 6) -> StrokeSample {
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy)
        guard length.isFinite, length > 0, toleranceDegrees.isFinite else { return end }
        let angle = atan2(dy, dx), target = (angle / (.pi / 4)).rounded() * (.pi / 4)
        guard abs(angle - target) <= min(22.5, max(0, toleranceDegrees)) * .pi / 180 else { return end }
        return StrokeSample(x: start.x + length * cos(target), y: start.y + length * sin(target))
    }
    public static func samples(from start: StrokeSample, to end: StrokeSample) -> [StrokeSample] {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard [start.x, start.y, end.x, end.y, length].allSatisfy(\.isFinite), length > 0 else { return [] }
        let count = Int(min(4096, max(2, ceil(length / 4))))
        return (0...count).map { i in
            let t = Double(i) / Double(count)
            return StrokeSample(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }
}
