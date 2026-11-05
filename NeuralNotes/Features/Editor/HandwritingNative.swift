import Foundation
import UIKit
import PencilKit
import NeuralNotesCore

/// Worker-safe analysis returns only Core values. Affine editing reuses the
/// native path verbatim; smoothing changes locations at the original indices.
enum HandwritingNative {
    struct Input: Sendable {
        let strokes: [HandwritingStroke]
        let analysis: HandwritingAnalysis
    }

    static func analyze(_ data: Data, selected: Set<Int>, lineHints: [SnapRect] = []) throws -> Input {
        let drawing = try PKDrawing(data: data)
        guard !selected.isEmpty, selected.allSatisfy({ drawing.strokes.indices.contains($0) }) else {
            throw HandwritingFailure.invalidSelection
        }
        guard selected.count <= HandwritingLayout.maximumStrokes else { throw HandwritingFailure.tooLarge }
        var result: [HandwritingStroke] = [], count = 0, layoutCount = 0
        for index in selected.sorted() {
            try Task.checkCancellation()
            let stroke = drawing.strokes[index]
            guard stroke.ink.inkType != .marker, !stroke.path.isEmpty else { continue }
            count += stroke.path.count
            guard count <= HandwritingLayout.maximumPoints else { throw HandwritingFailure.tooLarge }
            let points = stroke.path.map { point -> StrokeSample in
                let position = point.location.applying(stroke.transform)
                return .init(x: position.x, y: position.y)
            }
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000_000 && abs($0.y) <= 10_000_000 }) else {
                throw HandwritingFailure.invalidSelection
            }
            // Erased portions must not determine word widths or baselines.
            // The full original point list is still used for smoothing.
            let visible: [StrokeSample]
            if let mask = stroke.mask {
                var length: CGFloat = 0, previous: CGPoint?
                for point in stroke.path {
                    guard point.location.x.isFinite, point.location.y.isFinite else { throw HandwritingFailure.invalidSelection }
                    if let previous { length += hypot(point.location.x - previous.x, point.location.y - previous.y) }
                    previous = point.location
                }
                guard length.isFinite else { throw HandwritingFailure.invalidSelection }
                var samples: [StrokeSample] = []
                // The remaining middle of a two-point path can be visible even
                // when neither original control point is inside the mask.
                let distance = max(1, length / 512)
                for point in stroke.path.interpolatedPoints(by: .distance(distance)).prefix(2048) where mask.contains(point.location) && point.opacity > 0.001 {
                    let world = point.location.applying(stroke.transform)
                    samples.append(.init(x: world.x, y: world.y))
                }
                visible = samples
            } else { visible = points }
            guard !visible.isEmpty else { continue }
            layoutCount += visible.count
            guard layoutCount <= HandwritingLayout.maximumPoints else { throw HandwritingFailure.tooLarge }
            result.append(.init(id: index, points: points, layoutPoints: visible))
        }
        return Input(strokes: result, analysis: try HandwritingLayout.analyze(result, lineHints: lineHints))
    }

    static func applying(_ proposal: HandwritingProposal, to drawing: PKDrawing, allowed: Set<Int>) throws -> PKDrawing {
        let ids = proposal.adjustments.map(\.strokeID)
        guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids).isSubset(of: allowed),
              ids.allSatisfy({ drawing.strokes.indices.contains($0) }) else { throw HandwritingFailure.invalidSelection }
        var strokes = drawing.strokes
        for adjustment in proposal.adjustments {
            let original = strokes[adjustment.strokeID], affine = adjustment.transform
            let determinant = affine.a * affine.d - affine.b * affine.c
            guard original.ink.inkType != .marker, affine.isFinite, determinant.isFinite,
                  determinant > 0.0001, determinant < 10_000 else { throw HandwritingFailure.invalidSelection }
            let transform = CGAffineTransform(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty)
            if let coordinates = adjustment.points {
                let native = original.transform
                let nativeDeterminant = native.a * native.d - native.b * native.c
                guard coordinates.count == original.path.count,
                      coordinates.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                      abs(nativeDeterminant) > 0.000001 else { throw HandwritingFailure.invalidSelection }
                let inverse = original.transform.inverted()
                let controls = zip(original.path, coordinates).enumerated().map { index, pair in
                    let (point, coordinate) = pair
                    if index == 0 || index == original.path.count - 1 { return point }
                    let location = CGPoint(x: coordinate.x, y: coordinate.y).applying(inverse)
                    return relocated(point, to: location)
                }
                let path = PKStrokePath(controlPoints: controls, creationDate: original.path.creationDate)
                strokes[adjustment.strokeID] = PKStroke(ink: original.ink, path: path,
                    transform: original.transform.concatenating(transform), mask: original.mask, randomSeed: original.randomSeed)
            } else {
                strokes[adjustment.strokeID] = PKStroke(ink: original.ink, path: original.path,
                    transform: original.transform.concatenating(transform), mask: original.mask, randomSeed: original.randomSeed)
            }
        }
        return PKDrawing(strokes: strokes)
    }

    private static func relocated(_ point: PKStrokePoint, to location: CGPoint) -> PKStrokePoint {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return PKStrokePoint(location: location, timeOffset: point.timeOffset, size: point.size,
                opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                secondaryScale: point.secondaryScale, threshold: point.threshold)
        }
        #endif
        return PKStrokePoint(location: location, timeOffset: point.timeOffset, size: point.size,
            opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude,
            secondaryScale: point.secondaryScale)
    }
}
