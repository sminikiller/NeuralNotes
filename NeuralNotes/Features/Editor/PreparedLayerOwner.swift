import UIKit
import PencilKit
import NeuralNotesCore

/// One editable native owner can contain preserved composition stages after a
/// merge. Prepare each leaf once, before the blend probes replay it. Raster
/// leaves share a total area budget; PDF leaves keep actual vector strokes.
@MainActor
struct PreparedLayerOwner {
    private struct Leaf {
        let group: LayerRenderGroup
        let native: PKDrawing?
        let prepared: PreparedLayerInk?
        let hot: PKDrawing
    }
    private indirect enum Node {
        case leaf(Double, Leaf)
        case group(Double, [Node])
    }
    private let root: Node?
    private let live: Leaf
    private let page: PageSnapshot
    private let package: URL
    private let bounds: CGRect
    private let scale: CGFloat
    private let hiding: Set<UUID>
    private let hidingTextID: UUID?
    private let vector: Bool
    private let rootToken: UUID?
    private let metadata: PageSnapshot

    init(group: LayerRenderGroup, page: PageSnapshot, package: URL, drawing: PKDrawing,
         bounds: CGRect, scale: CGFloat, vector: Bool = false, transparent: Bool = false, signatures supplied: [String]? = nil,
         hot: Set<String> = [], hiding: Set<UUID> = [], hidingTextID: UUID? = nil,
         rootToken: UUID? = nil, previous: PreparedLayerOwner? = nil) {
        self.page = page; self.package = package; self.bounds = bounds; self.scale = scale
        self.hiding = hiding; self.hidingTextID = hidingTextID; self.vector = vector; self.rootToken = rootToken
        let normalized = LayerScene.fingerprint(page, owner: group.layer.id); metadata = normalized
        let reuseRoot = !vector && rootToken != nil && previous?.rootToken == rootToken && previous?.metadata == normalized &&
            previous?.bounds == bounds && previous?.scale == scale && previous?.hiding == hiding && previous?.hidingTextID == hidingTextID
        let keys = supplied ?? EditorInkSignatures.make(drawing)
        let pairs = zip(keys, drawing.strokes)
        let native = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        let allObjects = PageLayers.ownedObjectIDs(in: page, layerID: group.layer.id)
        let allMarks = Set(group.ordinaryMarkupIDs + group.wordMarkupIDs)
        let composition = group.layer.composition?.pruning(objects: allObjects, markups: allMarks, strokes: Set(keys))
        let claimedInk = composition?.strokeReferences ?? []
        let claimedObjects = composition?.objectReferences ?? []
        let claimedMarks = composition?.markupReferences ?? []
        var inkArea: CGFloat = 0
        func area(_ value: LayerComposition) {
            if let children = value.children { for child in children { area(child) }; return }
            let subset = PKDrawing(strokes: (value.strokes ?? []).compactMap { native[$0] })
            let region = subset.bounds.insetBy(dx: -2, dy: -2).intersection(bounds)
            if !region.isNull, !region.isEmpty { inkArea += region.width * region.height }
        }
        if !reuseRoot, let composition { area(composition) }
        let remainderKeys = keys.filter { !claimedInk.contains($0) }
        let rasterScale = min(scale, sqrt(1_500_000 / max(1, inkArea)))
        func leaf(_ value: LayerComposition, rasterScale: CGFloat) -> Leaf {
            let strokes = value.strokes ?? [], subset = PKDrawing(strokes: strokes.compactMap { native[$0] })
            let region = subset.bounds.insetBy(dx: -2, dy: -2).intersection(bounds)
            let ink = !vector && !transparent && !region.isNull && !region.isEmpty ? PreparedLayerInk(drawing: subset, bounds: region, scale: rasterScale) : nil
            let emphasized = PKDrawing(strokes: strokes.filter(hot.contains).compactMap { key in
                native[key].map { PKStroke(ink: PKInk(.pen, color: .systemTeal), path: $0.path,
                    transform: $0.transform, mask: $0.mask, randomSeed: $0.randomSeed) }
            })
            return Leaf(group: group.restricting(objects: Set(value.objects ?? []), markups: Set(value.markups ?? [])),
                native: vector || transparent ? subset : nil, prepared: ink, hot: emphasized)
        }
        func node(_ value: LayerComposition) -> Node {
            if let children = value.children { return .group(value.opacity, children.map(node)) }
            return .leaf(value.opacity, leaf(value, rasterScale: rasterScale))
        }
        root = reuseRoot ? previous?.root : composition.map(node)
        let remainder = LayerComposition(strokes: remainderKeys,
            objects: page.orderedObjectIDs.filter { allObjects.contains($0) && !claimedObjects.contains($0) },
            markups: (group.ordinaryMarkupIDs + group.wordMarkupIDs).filter { !claimedMarks.contains($0) })
        live = leaf(remainder, rasterScale: scale)
    }

    /// Caller applies the owner's current group opacity around this operation.
    func draw(in context: CGContext, marker: CGPath? = nil, color: UIColor? = nil, isolated: Bool = false) {
        if let root { draw(root, in: context, isolated: isolated) }
        draw(live, in: context, marker: marker, color: color)
    }
    private func draw(_ node: Node, in context: CGContext, isolated: Bool) {
        switch node {
        case .leaf(let opacity, let leaf):
            blend(opacity, in: context, isolated: isolated) { draw(leaf, in: $0) }
        case .group(let opacity, let children):
            blend(opacity, in: context, isolated: isolated) { target in
                for child in children { draw(child, in: target, isolated: isolated) }
            }
        }
    }
    private func blend(_ opacity: Double, in context: CGContext, isolated: Bool, content: (CGContext) -> Void) {
        if isolated { LayerBlendCompositor.drawIsolatedGroup(opacity: opacity, in: context, content: content) }
        else { LayerBlendCompositor.drawGroup(opacity: opacity, bounds: bounds, in: context, uniqueText: vector, content: content) }
    }
    private func draw(_ leaf: Leaf, in context: CGContext, marker: CGPath? = nil, color: UIColor? = nil) {
        PageRenderer.drawLayerContent(leaf.group, page: page, package: package, in: context,
            hidingObjectIDs: hiding, hidingTextID: hidingTextID) { target in
            leaf.prepared?.drawMarkers(in: target)
            if let marker, let color {
                target.saveGState(); target.setBlendMode(.multiply); target.setAlpha(0.25)
                target.setFillColor(color.withAlphaComponent(1).cgColor); target.addPath(marker); target.fillPath(); target.restoreGState()
            }
            leaf.prepared?.drawPens(in: target)
            if let native = leaf.native { LegibleInkRenderer.draw(native, in: target, bounds: bounds, scale: scale, vector: vector) }
            if !leaf.hot.strokes.isEmpty {
                target.saveGState(); target.setAlpha(0.65)
                LegibleInkRenderer.draw(leaf.hot, in: target, bounds: bounds, scale: scale, vector: vector)
                target.restoreGState()
            }
        }
    }
}
