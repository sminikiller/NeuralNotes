import Foundation

public enum LayerMergeFailure: LocalizedError {
    case bottom, unavailable, tooComplex
    public var errorDescription: String? {
        switch self {
        case .bottom: return "Questo livello non ha un livello sotto."
        case .unavailable: return "Mostra e sblocca entrambi i livelli prima di unirli."
        case .tooComplex: return "Questa unione supera il limite di composizione. I livelli originali sono stati conservati."
        }
    }
}
public struct LayerMergePlan: Sendable {
    public let page: PageSnapshot
    public let sourceID: UUID
    public let targetID: UUID

    /// The caller concatenates the actual target/source PKStroke values and
    /// provides the resulting native signatures. No paths, pressure or seeds
    /// are invented to distinguish identical copied strokes.
    public static func make(page original: PageSnapshot, sourceID: UUID, targetStrokes: [String],
                            sourceStrokes: [String], mergedStrokes: [String]) throws -> Self {
        try PageValidation.validate(original)
        let layers = PageLayers.ordered(in: original)
        guard let index = layers.firstIndex(where: { $0.id == sourceID }), index > 0 else { throw LayerMergeFailure.bottom }
        let source = layers[index], target = layers[index - 1]
        guard PageLayers.editable(source.id, page: original), PageLayers.editable(target.id, page: original) else { throw LayerMergeFailure.unavailable }
        guard mergedStrokes.count == targetStrokes.count + sourceStrokes.count,
              Set(targetStrokes).count == targetStrokes.count, Set(sourceStrokes).count == sourceStrokes.count,
              Set(mergedStrokes).count == mergedStrokes.count else { throw LibraryFailure.corruptDocument }
        let targetMap = Dictionary(uniqueKeysWithValues: zip(targetStrokes, mergedStrokes.prefix(targetStrokes.count)))
        let sourceMap = Dictionary(uniqueKeysWithValues: zip(sourceStrokes, mergedStrokes.dropFirst(targetStrokes.count)))
        func captured(_ layer: PageLayer, strokes: [String], mapping: [String: String]) -> LayerComposition {
            let owned = PageLayers.ownedObjectIDs(in: original, layerID: layer.id)
            let ids = original.orderedObjectIDs.filter(owned.contains)
            let marks = (original.pdfMarkups ?? []).filter { ($0.layerID ?? original.id) == layer.id }.map(\.id)
            return LayerComposition.capturing(layer.composition, opacity: layer.opacity ?? 1, strokes: strokes, objects: ids, markups: marks).remapping(strokes: mapping)
        }
        let composition = LayerComposition(children: [captured(target, strokes: targetStrokes, mapping: targetMap),
            captured(source, strokes: sourceStrokes, mapping: sourceMap)]).normalized
        var page = original
        let owner: UUID? = target.id == page.id ? nil : target.id
        func owns(_ id: UUID?) -> Bool { (id ?? original.id) == source.id }
        for i in page.texts.indices where owns(page.texts[i].layerID) { page.texts[i].layerID = owner }
        for i in page.images.indices where owns(page.images[i].layerID) { page.images[i].layerID = owner }
        if var values = page.shapes {
            for i in values.indices where owns(values[i].layerID) { values[i].layerID = owner; values[i].audioAnchor?.layerID = owner }; page.shapes = values
        }
        if var values = page.connectors {
            for i in values.indices where owns(values[i].layerID) { values[i].layerID = owner; values[i].audioAnchor?.layerID = owner }; page.connectors = values
        }
        if var values = page.tapes { for i in values.indices where owns(values[i].layerID) { values[i].layerID = owner }; page.tapes = values }
        if var values = page.pdfMarkups { for i in values.indices where owns(values[i].layerID) { values[i].layerID = owner }; page.pdfMarkups = values }
        page.anchors = original.anchors.map { anchor in
            let oldOwner = anchor.layerID ?? original.id
            guard oldOwner == source.id || oldOwner == target.id else { return anchor }
            var value = anchor; value.layerID = owner
            let map = oldOwner == source.id ? sourceMap : targetMap
            if (anchor.strokeOccurrence == nil || anchor.strokeOccurrence == 0), let signature = map[anchor.signature] {
                value.signature = signature; value.strokeOccurrence = 0
            } else { value.strokeOccurrence = max(1, anchor.strokeOccurrence ?? 1) }
            return value
        }
        var next = layers
        if source.id == page.id {
            // Base is a persistent page identity, even after it has been moved
            // above another owner. Keep an empty Base instead of deleting it.
            next[index].composition = nil; page.drawingFile = nil; page.previousDrawingFile = nil
        } else { next.remove(at: index) }
        next[index - 1].composition = composition; next[index - 1].opacity = nil
        page.layers = next
        do {
            try composition.validate(ownedObjects: PageLayers.ownedObjectIDs(in: page, layerID: target.id),
                ownedMarkups: Set((page.pdfMarkups ?? []).filter { ($0.layerID ?? page.id) == target.id }.map(\.id)))
        } catch { throw LayerMergeFailure.tooComplex }
        try PageValidation.validate(page)
        return Self(page: page, sourceID: source.id, targetID: target.id)
    }
}
