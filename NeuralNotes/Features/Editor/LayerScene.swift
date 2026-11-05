import UIKit
import PencilKit
import NeuralNotesCore

/// One visible region, four composition stages. The host retains at most one
/// small whole-page fallback (12MiB) and one detail region (36MiB). Inactive
/// owners are decoded sequentially and discarded after producing two maps.
@MainActor
struct LayerScene {
    static let fallbackBudget = 12 << 20
    static let detailBudget = 36 << 20
    let fingerprint: PageSnapshot
    let inactiveFingerprint: PageSnapshot
    let ownerID: UUID
    let bounds: CGRect
    let requestedScale: CGFloat
    let scale: CGFloat
    let below: LayerBlendCompositor.Maps?
    let under: LayerBlendCompositor.Maps?
    let over: LayerBlendCompositor.Maps?
    let above: LayerBlendCompositor.Maps?
    let hiding: Set<UUID>
    let hidingTextID: UUID?
    var byteCost: Int { (below?.byteCost ?? 0) + (under?.byteCost ?? 0) + (over?.byteCost ?? 0) + (above?.byteCost ?? 0) }

    static func fingerprint(_ page: PageSnapshot, owner: UUID, inactiveOnly: Bool = false) -> PageSnapshot {
        var value = page; value.revision = 0; value.lastEditedAt = nil; value.anchors = []; value.recognizedText = ""
        value.lockedObjects = nil
        if owner == page.id { value.drawingFile = nil; value.previousDrawingFile = nil }
        if var layers = value.layers {
            for i in layers.indices {
                layers[i].name = "_"; layers[i].isLocked = false
                if layers[i].id == owner {
                    layers[i].drawingFile = nil; layers[i].previousDrawingFile = nil
                    if inactiveOnly { layers[i].opacity = nil; layers[i].isVisible = true }
                }
            }
            value.layers = layers
        }
        if var shapes = value.shapes { for i in shapes.indices { shapes[i].audioAnchor = nil }; value.shapes = shapes }
        if var edges = value.connectors { for i in edges.indices { edges[i].audioAnchor = nil }; value.connectors = edges }
        if inactiveOnly {
            func inactive(_ ownerID: UUID?) -> Bool { (ownerID ?? page.id) != owner }
            let edges = (page.connectors ?? []).filter { inactive($0.layerID) }
            // A connector on another owner can still depend on the geometry of
            // an active object. Keep those targets in the comparison key only.
            let targets = Set(edges.flatMap { [$0.from.objectID, $0.to.objectID].compactMap { $0 } })
            value.texts.removeAll { !inactive($0.layerID) && !targets.contains($0.id) }
            value.images.removeAll { !inactive($0.layerID) && !targets.contains($0.id) }
            value.shapes = value.shapes?.filter { inactive($0.layerID) || targets.contains($0.id) }
            value.tapes = value.tapes?.filter { inactive($0.layerID) || targets.contains($0.id) }
            value.connectors = value.connectors?.filter { inactive($0.layerID) }
            value.pdfMarkups = value.pdfMarkups?.filter { inactive($0.layerID) }
            value.pruneObjectReferences()
        }
        return value
    }

    static func prepare(page: PageSnapshot, owner: UUID, workspace: DocumentWorkspace, bounds: CGRect,
                        requestedScale: CGFloat, budget: Int, previous: LayerScene? = nil,
                        hiding: Set<UUID> = [], hidingTextID: UUID? = nil) async throws -> LayerScene {
        try PageValidation.validate(page); try Task.checkCancellation()
        let plan = try LayerRenderPlan.make(page: page, selection: .all)
        guard let activeIndex = plan.firstIndex(where: { $0.layer.id == owner }),
              !bounds.isEmpty, [bounds.minX, bounds.minY, bounds.width, bounds.height, requestedScale].allSatisfy(\.isFinite),
              requestedScale > 0, budget >= 4096 else { throw LibraryFailure.corruptDocument }
        let active = plan[activeIndex]
        let lower = Array(plan.prefix(activeIndex)).filter { $0.layer.isVisible && $0.opacity > 0 && hasContent($0) }
        let upper = Array(plan.dropFirst(activeIndex + 1)).filter { $0.layer.isVisible && $0.opacity > 0 && hasContent($0) }
        let visible = active.layer.isVisible && active.opacity > 0
        let hasUnder = active.layer.composition == nil && visible && (!active.underObjectIDs.isEmpty || !active.underMarkerIDs.isEmpty || !active.ordinaryMarkupIDs.isEmpty || !active.wordMarkupIDs.isEmpty)
        let hasOver = active.layer.composition == nil && visible && (!active.aboveObjectIDs.isEmpty || !active.tapeIDs.isEmpty)
        let mapCount = 2 * [!lower.isEmpty, hasUnder, hasOver, !upper.isEmpty].filter { $0 }.count
        let area = bounds.width * bounds.height
        let affordable = sqrt(CGFloat(budget) * 0.8 / (max(1, CGFloat(mapCount)) * 4 * max(1, area)))
        let dimensionLimit = 8192 / max(1, max(bounds.width, bounds.height))
        let scale = max(0.0001, min(requestedScale, affordable, sqrt(4_000_000 / max(1, area)), dimensionLimit))
        let signature = fingerprint(page, owner: owner), inactive = fingerprint(page, owner: owner, inactiveOnly: true)
        let reuse = previous?.ownerID == owner && previous?.bounds == bounds && previous?.scale == scale && previous?.inactiveFingerprint == inactive && previous?.hiding == hiding && previous?.hidingTextID == hidingTextID
        let below: LayerBlendCompositor.Maps?
        let above: LayerBlendCompositor.Maps?
        if reuse { below = previous?.below; above = previous?.above }
        else {
            below = try await aggregate(lower, page: page, workspace: workspace, bounds: bounds, scale: scale, hiding: hiding, hidingTextID: hidingTextID)
            above = try await aggregate(upper, page: page, workspace: workspace, bounds: bounds, scale: scale, hiding: hiding, hidingTextID: hidingTextID)
        }
        try Task.checkCancellation()
        let under = hasUnder ? LayerBlendCompositor.maps(opacity: 1, bounds: bounds, scale: scale) {
            PageRenderer.drawLayerUnder(active, page: page, package: workspace.package, in: $0, hidingObjectIDs: hiding, hidingTextID: hidingTextID)
        } : nil
        let over = hasOver ? LayerBlendCompositor.maps(opacity: 1, bounds: bounds, scale: scale) {
            PageRenderer.drawLayerAbove(active, page: page, package: workspace.package, in: $0, hidingObjectIDs: hiding, hidingTextID: hidingTextID)
        } : nil
        guard (!hasUnder || under != nil), (!hasOver || over != nil) else { throw WorkspaceFailure.oversizedImport }
        let scene = LayerScene(fingerprint: signature, inactiveFingerprint: inactive, ownerID: owner, bounds: bounds,
            requestedScale: requestedScale, scale: scale, below: below, under: under, over: over, above: above,
            hiding: hiding, hidingTextID: hidingTextID)
        guard scene.byteCost <= budget else { throw WorkspaceFailure.oversizedImport }
        return scene
    }

    private static func hasContent(_ group: LayerRenderGroup) -> Bool {
        group.drawingFile != nil || !group.ordinaryMarkupIDs.isEmpty || !group.underObjectIDs.isEmpty ||
            !group.wordMarkupIDs.isEmpty || !group.underMarkerIDs.isEmpty || !group.aboveObjectIDs.isEmpty || !group.tapeIDs.isEmpty
    }
    private static func aggregate(_ groups: [LayerRenderGroup], page: PageSnapshot, workspace: DocumentWorkspace,
                                  bounds: CGRect, scale: CGFloat, hiding: Set<UUID>, hidingTextID: UUID?) async throws -> LayerBlendCompositor.Maps? {
        var result: LayerBlendCompositor.Maps?
        for group in groups {
            try Task.checkCancellation()
            let next = try await ownerMaps(group, page: page, workspace: workspace, bounds: bounds, scale: scale, hiding: hiding, hidingTextID: hidingTextID)
            try Task.checkCancellation()
            if let previous = result {
                result = autoreleasepool {
                    LayerBlendCompositor.maps(opacity: 1, bounds: bounds, scale: scale) { context in
                        previous.draw(in: context, bounds: bounds); next.draw(in: context, bounds: bounds)
                    }
                }
            } else { result = next }
            await Task.yield()
        }
        return result
    }
    private static func ownerMaps(_ group: LayerRenderGroup, page: PageSnapshot, workspace: DocumentWorkspace,
                                  bounds: CGRect, scale: CGFloat, hiding: Set<UUID>, hidingTextID: UUID?) async throws -> LayerBlendCompositor.Maps {
        let value = try await LayerDrawingReader.read(page: page, layerID: group.layer.id, workspace: workspace)
        try Task.checkCancellation()
        // No await after decoding: this native archive is released before the
        // caller starts the next owner, even when other hosts are preparing.
        return try autoreleasepool {
            let owner = PreparedLayerOwner(group: group, page: page, package: workspace.package, drawing: value.drawing,
                bounds: bounds, scale: scale, hiding: hiding, hidingTextID: hidingTextID)
            guard let maps = LayerBlendCompositor.maps(opacity: group.opacity, bounds: bounds, scale: scale, content: { owner.draw(in: $0) }) else { throw WorkspaceFailure.oversizedImport }
            return maps
        }
    }
}
