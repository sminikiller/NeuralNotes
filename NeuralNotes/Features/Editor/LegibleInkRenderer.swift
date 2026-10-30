import UIKit
import PencilKit

/// One composition contract for live patches, thumbnails, images and PDF:
/// marker uses multiply against the actual paper/PDF, then ordinary ink is
/// drawn above it. The saved PKDrawing and its native masks remain untouched.
@MainActor
enum LegibleInkRenderer {
    static func draw(_ drawing: PKDrawing, in context: CGContext, bounds: CGRect, scale: CGFloat, vector: Bool = false) {
        if vector { VectorInkRenderer.draw(drawing, in: context); return }
        var markers: [PKStroke] = [], pens: [PKStroke] = []
        for stroke in drawing.strokes where stroke.renderBounds.intersects(bounds) {
            if stroke.ink.inkType == .marker { markers.append(stroke) } else { pens.append(stroke) }
        }
        if !markers.isEmpty {
            context.saveGState(); context.setBlendMode(.multiply)
            PaperInk.image(PKDrawing(strokes: markers), from: bounds, scale: scale).draw(in: bounds)
            context.restoreGState()
        }
        if !pens.isEmpty { PaperInk.image(PKDrawing(strokes: pens), from: bounds, scale: scale).draw(in: bounds) }
    }
}
