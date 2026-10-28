import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum PreciseStrokeGeometry {
    static func shape(kind: ShapeKind, points: [StrokeSample]) -> ShapeElement? {
        guard let a = points.first, let b = points.last else { return nil }
        if let value = ShapeRecognizer.recognize(points), value.shape.kind == kind { return value.shape }
        if kind == .line || kind == .arrow {
            let ends = kind == .line ? HeldShapeRecognition.lineEndpoints(points) : HeldShapeRecognition.arrowEndpoints(points)
            let first = ends?.0 ?? a, last = ShapeRecognizer.snappedEnd(first, ends?.1 ?? b)
            return ShapeElement.dragged(kind: kind, from: first, to: last, color: .black, lineWidth: 3)
        }
        let x = points.map(\.x).min() ?? a.x, y = points.map(\.y).min() ?? a.y
        let width = max(1, (points.map(\.x).max() ?? b.x) - x), height = max(1, (points.map(\.y).max() ?? b.y) - y)
        return ShapeElement(kind: kind, x: x, y: y, width: width, height: height)
    }
    static func path(kind: ShapeKind, points: [StrokeSample]) -> UIBezierPath {
        guard let shape = shape(kind: kind, points: points) else { return UIBezierPath() }
        let result = UIBezierPath(cgPath: ShapePathRendering.path(ShapeGeometry.path(for: shape)))
        for arrow in ShapeGeometry.arrowPaths(for: shape) { result.append(UIBezierPath(cgPath: ShapePathRendering.path(arrow))) }
        return result
    }
    static func stroke(kind: ShapeKind, points: [StrokeSample], original: PKStroke) -> PKStroke {
        guard let shape = shape(kind: kind, points: points) else { return original }
        let paths = [ShapeGeometry.path(for: shape)] + ShapeGeometry.arrowPaths(for: shape)
        var locations: [StrokeSample] = []
        for path in paths {
            for line in ShapeGeometry.polylines(path, steps: 64) {
                guard let first = line.first else { continue }
                locations.append(first)
                for index in 1..<line.count {
                    locations += PreciseLine.samples(from: line[index - 1], to: line[index]).dropFirst()
                }
            }
        }
        let sample = original.path.first
        let size = sample?.size ?? CGSize(width: 3, height: 3)
        let controls = locations.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: Double(index) * 0.01,
                size: size, opacity: sample?.opacity ?? 1, force: sample?.force ?? 1,
                azimuth: sample?.azimuth ?? 0, altitude: sample?.altitude ?? .pi / 2)
        }
        guard controls.count > 1 else { return original }
        return PKStroke(ink: original.ink, path: PKStrokePath(controlPoints: controls, creationDate: original.path.creationDate))
    }
}
