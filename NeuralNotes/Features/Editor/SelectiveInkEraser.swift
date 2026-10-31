import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
enum SelectiveInkEraser {
    /// Compatibility adapter for one-shot marker erasure. Live erasing uses
    /// SelectiveEraseSession's gesture cache instead of recomputing outlines.
    static func erase(_ drawing: PKDrawing, samples: [StrokeSample], width: Double, wholeStroke: Bool) -> (PKDrawing, Bool) {
        guard let area = EraserStrokeGeometry.area(samples: samples, width: width) else { return (drawing, false) }
        var result: [PKStroke] = [], changed = false
        for stroke in drawing.strokes {
            guard stroke.ink.inkType == .marker, stroke.renderBounds.intersects(area.boundingBoxOfPath) else { result.append(stroke); continue }
            if let cut = EraserStrokeGeometry.cut(stroke, visible: EraserStrokeGeometry.visible(stroke), area: area, whole: wholeStroke) {
                changed = true
                if let kept = cut.stroke { result.append(kept) }
            } else { result.append(stroke) }
        }
        return (changed ? PKDrawing(strokes: result) : drawing, changed)
    }
}
