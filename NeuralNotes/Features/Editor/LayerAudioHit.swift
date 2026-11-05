import UIKit
import PencilKit
import NeuralNotesCore

/// Inspect one visible owner at a time. Matching a bounding rectangle alone
/// would seek unrelated handwriting; use the native interpolated curve.
@MainActor
enum LayerAudioHit {
    static func anchor(at point: CGPoint, tolerance: CGFloat, page: PageSnapshot,
                       live: PKDrawing, owner: UUID, workspace: DocumentWorkspace, zoom: CGFloat) async throws -> StrokeAnchor? {
        var nearest: (StrokeAnchor, CGFloat)?
        let visible = Set(PageLayers.ordered(in: page).filter { $0.isVisible && ($0.opacity ?? 1) > 0 }.map(\.id))
        for shape in (page.shapes ?? []).reversed() where visible.contains(shape.layerID ?? page.id) {
            if let anchor = shape.audioAnchor, ShapeGeometry.hit(.init(x: point.x, y: point.y), shape: shape, zoom: zoom) { return anchor }
        }
        let objects = DiagramObjects.make(page)
        for edge in (page.connectors ?? []).reversed() where visible.contains(edge.layerID ?? page.id) {
            if let anchor = edge.audioAnchor, ConnectorGeometry.hit(.init(x: point.x, y: point.y), connector: edge, objects: objects, zoom: zoom) { return anchor }
        }
        for layer in PageLayers.ordered(in: page).reversed() where visible.contains(layer.id) {
            try Task.checkCancellation()
            guard page.anchors.contains(where: { ($0.layerID ?? page.id) == layer.id }) else { continue }
            let drawing: PKDrawing
            if layer.id == owner { drawing = live }
            else { drawing = try await LayerDrawingReader.read(page: page, layerID: layer.id, workspace: workspace).drawing }
            let signatures = EditorInkSignatures.make(drawing)
            let keys = LayerStrokeTimeline.keys(signatures: signatures, pageID: page.id, layerID: layer.id)
            for (index, stroke) in drawing.strokes.enumerated() {
                guard stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
                let key = keys[index]
                let matches = page.anchors.filter { ($0.layerID ?? page.id) == layer.id && $0.signature == key.signature }
                guard let anchor = matches.first(where: { $0.strokeOccurrence == key.occurrence }) ?? matches.first(where: { $0.strokeOccurrence == nil }) else { continue }
                let distance = distance(point, to: stroke)
                if distance <= tolerance, nearest == nil || distance < nearest!.1 { nearest = (anchor, distance) }
            }
        }
        return nearest?.0
    }
    private static func distance(_ point: CGPoint, to stroke: PKStroke) -> CGFloat {
        let samples = stroke.path.interpolatedPoints(by: .distance(6)).map { $0.location.applying(stroke.transform) }
        var best = CGFloat.greatestFiniteMagnitude
        if let first = samples.first { best = hypot(first.x - point.x, first.y - point.y) }
        for (a, b) in zip(samples, samples.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            best = min(best, hypot(point.x - a.x - t * dx, point.y - a.y - t * dy))
        }
        return best
    }
}
