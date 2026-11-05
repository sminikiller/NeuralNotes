import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func prepareLayerPresentation() async {
        guard page?.layers != nil, let host = pagePresenter as? CanvasHost else { return }
        host.synchronizePage()
        if !(await host.layeredScene.prepareForInput(host)) {
            error = error ?? "Modifica salvata. Riapri il quaderno per preparare la visualizzazione dei livelli."
        }
    }
    func scopedSelectionIDs(in page: PageSnapshot, includingConnectors: Bool = true) -> Set<UUID> {
        let ids = includingConnectors ? page.includingInternalConnectors(selectedIDs) : selectedIDs
        guard page.layers != nil else { return ids }
        return ids.intersection(PageLayers.editableObjectIDs(in: page, layerID: drawingLayerID ?? page.id))
    }
    func rebaseLayerInkMembership(from original: PageSnapshot, old: PKDrawing, new: PKDrawing,
                                  retainedIndices: [Int], includeAudio: Bool = true) {
        guard original.layers != nil, var value = page, value.id == original.id else { return }
        let owner = drawingLayerID ?? original.id
        let oldKeys = EditorInkSignatures.make(old), newKeys = EditorInkSignatures.make(new)
        if let index = value.layers?.firstIndex(where: { $0.id == owner }) {
            value.layers?[index].composition = original.layers?.first(where: { $0.id == owner })?.composition?
                .replacingStrokes(old: oldKeys, new: newKeys, retainedIndices: retainedIndices)
        }
        if includeAudio {
            value.anchors = LayerStrokeTimeline.replacing(anchors: original.anchors, oldSignatures: oldKeys,
                newSignatures: newKeys, retainedOriginalIndices: retainedIndices, pageID: original.id, layerID: owner)
        }
        page = value
    }
}

extension PageSnapshot {
    func selectionComposition(owner: UUID, signatures: [String], inkIndices: Set<Int>, objectIDs: Set<UUID>) -> LayerComposition? {
        guard let layer = PageLayers.ordered(in: self).first(where: { $0.id == owner }),
              layer.composition != nil || (layer.opacity ?? 1) != 1 else { return nil }
        let owned = PageLayers.ownedObjectIDs(in: self, layerID: owner)
        let value = LayerComposition.capturing(layer.composition, opacity: layer.opacity ?? 1, strokes: signatures,
            objects: orderedObjectIDs.filter(owned.contains), markups: [])
        return value.pruning(objects: objectIDs, markups: [], strokes: Set(signatures.enumerated().filter { inkIndices.contains($0.offset) }.map(\.element)))
    }
    mutating func appendComposition(_ incoming: LayerComposition?, owner: UUID, original: PageSnapshot, originalInk: [String]) throws {
        guard let incoming else { return }
        let old = PageLayers.ordered(in: original).first { $0.id == owner }
        let owned = PageLayers.ownedObjectIDs(in: original, layerID: owner)
        let marks = (original.pdfMarkups ?? []).filter { ($0.layerID ?? original.id) == owner }.map(\.id)
        let previous = LayerComposition.capturing(old?.composition, opacity: 1, strokes: originalInk,
            objects: original.orderedObjectIDs.filter(owned.contains), markups: marks)
        if layers == nil { layers = PageLayers.ordered(in: self) }
        guard let index = layers?.firstIndex(where: { $0.id == owner }) else { throw PageLayerFailure.missing }
        let composition = LayerComposition(children: [previous, incoming]).normalized
        do {
            try composition.validate(ownedObjects: PageLayers.ownedObjectIDs(in: self, layerID: owner),
                ownedMarkups: Set((pdfMarkups ?? []).filter { ($0.layerID ?? id) == owner }.map(\.id)))
        } catch { throw LayerMergeFailure.tooComplex }
        layers?[index].composition = composition
        try PageValidation.validate(self)
    }
    /// A clipboard/cross-page payload belongs to its destination owner, never
    /// to IDs from a different page or notebook. Does not copy layer headers.
    mutating func assignObjectOwner(_ owner: UUID?) {
        for i in texts.indices { texts[i].layerID = owner }
        for i in images.indices { images[i].layerID = owner }
        if var values = shapes {
            for i in values.indices { values[i].layerID = owner; values[i].audioAnchor?.layerID = owner }; shapes = values
        }
        if var values = connectors {
            for i in values.indices { values[i].layerID = owner; values[i].audioAnchor?.layerID = owner }; connectors = values
        }
        if var values = tapes { for i in values.indices { values[i].layerID = owner }; tapes = values }
        if var values = pdfMarkups { for i in values.indices { values[i].layerID = owner }; pdfMarkups = values }
    }
}
