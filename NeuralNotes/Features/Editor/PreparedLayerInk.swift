import UIKit
import PencilKit

/// Rasterize only the visible native ink, once for the two blend probes. Pens
/// keep PencilKit's texture/mask/pressure; marker geometry remains Multiply.
/// No saved stroke, native editing history or source file is changed.
@MainActor
struct PreparedLayerInk {
    private let markers: UIImage?
    private let pens: UIImage?
    let bounds: CGRect
    init(drawing: PKDrawing, bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        let pixels = max(1, bounds.width * bounds.height)
        let boundedScale = max(0.0001, min(scale, sqrt(1_500_000 / pixels), 8192 / max(1, max(bounds.width, bounds.height))))
        var markerStrokes: [PKStroke] = [], penStrokes: [PKStroke] = []
        for stroke in drawing.strokes where stroke.renderBounds.intersects(bounds) {
            if stroke.ink.inkType == .marker { markerStrokes.append(stroke) }
            else { penStrokes.append(stroke) }
        }
        if markerStrokes.isEmpty { markers = nil }
        else {
            let native = PKDrawing(strokes: markerStrokes)
            let format = UIGraphicsImageRendererFormat(); format.scale = boundedScale; format.opaque = true
            format.preferredRange = .standard
            markers = UIGraphicsImageRenderer(size: bounds.size, format: format).image { result in
                let context = result.cgContext; context.translateBy(x: -bounds.minX, y: -bounds.minY)
                context.setFillColor(UIColor.white.cgColor); context.fill(bounds)
                VectorInkRenderer.draw(native, in: context)
            }
        }
        pens = penStrokes.isEmpty ? nil : PaperInk.image(PKDrawing(strokes: penStrokes), from: bounds, scale: boundedScale)
    }
    func drawMarkers(in context: CGContext) {
        guard let markers else { return }
        context.saveGState(); markers.draw(in: bounds, blendMode: .multiply, alpha: 1); context.restoreGState()
    }
    func drawPens(in context: CGContext) {
        guard let pens else { return }
        context.saveGState(); context.setBlendMode(.normal); pens.draw(in: bounds); context.restoreGState()
    }
    func draw(in context: CGContext) { drawMarkers(in: context); drawPens(in: context) }
}

/// A native append gesture reuses its pre-gesture ink. Only the delivered new
/// strokes are rasterized per sample, not an entire semester of handwriting.
/// Erasure/replacement deliberately bypasses this optimization.
@MainActor
final class ActiveLayerInkCache {
    private var baselineToken: UUID?
    private var currentToken: UUID?
    private var localToken: UUID?
    private var bounds = CGRect.zero
    private var scale: CGFloat = 0
    private var baseline: PreparedLayerInk?
    private var current: PreparedLayerInk?
    private(set) var baselineBuilds = 0
    private(set) var currentBuilds = 0
    func clear() {
        baselineToken = nil; currentToken = nil; localToken = nil; baseline = nil; current = nil
    }
    func prepare(drawing: PKDrawing, baseline base: PKDrawing?, baselineToken: UUID?,
                 token: UUID, localToken: UUID, bounds: CGRect, scale: CGFloat) {
        let geometryChanged = self.bounds != bounds || self.scale != scale
        let append = base != nil && baselineToken != nil && drawing.strokes.count >= (base?.strokes.count ?? 0)
        if geometryChanged || self.baselineToken != baselineToken || (!append && baseline != nil) {
            baseline = append ? PreparedLayerInk(drawing: base!, bounds: bounds, scale: scale) : nil
            if append { baselineBuilds += 1 }
            self.baselineToken = append ? baselineToken : nil
            currentToken = nil
        }
        if geometryChanged || currentToken != token || self.localToken != localToken {
            let delta = append ? PKDrawing(strokes: Array(drawing.strokes.dropFirst(base!.strokes.count))) : drawing
            let region = append ? delta.bounds.insetBy(dx: -2, dy: -2).intersection(bounds) : bounds
            current = region.isNull || region.isEmpty ? nil : PreparedLayerInk(drawing: delta, bounds: region, scale: scale)
            currentBuilds += 1; currentToken = token; self.localToken = localToken
        }
        self.bounds = bounds; self.scale = scale
    }
    func drawMarkers(in context: CGContext) { baseline?.drawMarkers(in: context); current?.drawMarkers(in: context) }
    func drawPens(in context: CGContext) { baseline?.drawPens(in: context); current?.drawPens(in: context) }
}
