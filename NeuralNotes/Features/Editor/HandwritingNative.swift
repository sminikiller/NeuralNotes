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
        var result: [HandwritingStroke] = [], count = 0
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
            // Erased portions must not determine word widths or baselines.
            // The full original point list is still used for smoothing.
            let visible = stroke.path.enumerated().compactMap { offset, point -> StrokeSample? in
                if let mask = stroke.mask, !mask.contains(point.location) { return nil }
                return points[offset]
            }
            guard !visible.isEmpty else { continue }
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
                guard coordinates.count == original.path.count,
                      coordinates.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                      abs(original.transform.determinant) > 0.000001 else { throw HandwritingFailure.invalidSelection }
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

private extension CGAffineTransform {
    var determinant: CGFloat { a * d - b * c }
}
