import PencilKit
import UIKit

/// PKDrawing archives contain native container identity. Reconstructing the
/// same vector strokes can change those bytes, even for an empty drawing.
/// Compare the complete public stroke state instead of container archives.
@MainActor
enum NativeInkComparison {
    static func equal(_ first: PKDrawing, _ second: PKDrawing, ignoringMarkers: Bool = false) -> Bool {
        let lhs = ignoringMarkers ? first.strokes.filter { $0.ink.inkType != .marker } : first.strokes
        let rhs = ignoringMarkers ? second.strokes.filter { $0.ink.inkType != .marker } : second.strokes
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            guard a.ink.inkType == b.ink.inkType, a.ink.color.isEqual(b.ink.color), a.transform == b.transform,
                  a.randomSeed == b.randomSeed, a.path.creationDate == b.path.creationDate, a.path.count == b.path.count else { return false }
            switch (a.mask, b.mask) {
            case (nil, nil): break
            case (let x?, let y?):
                guard x.usesEvenOddFillRule == y.usesEvenOddFillRule, x.cgPath == y.cgPath else { return false }
            default: return false
            }
            for (x, y) in zip(a.path, b.path) {
                guard x.location == y.location, x.size == y.size, x.timeOffset == y.timeOffset,
                      x.opacity == y.opacity, x.force == y.force, x.azimuth == y.azimuth, x.altitude == y.altitude else { return false }
            }
        }
        return true
    }
}
