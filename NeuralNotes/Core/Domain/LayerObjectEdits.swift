import Foundation

/// Defense at the editor's common metadata mutation boundary. Geometry helpers
/// still receive the complete page, so connectors may resolve targets on other
/// layers without making those targets editable. Legacy pages pass through.
public enum LayerObjectEdits {
    public static func restricted(_ proposed: PageSnapshot, from original: PageSnapshot, activeLayerID: UUID) -> PageSnapshot {
        guard original.layers != nil else { return proposed }
        guard proposed.id == original.id else { return original }
        guard proposed != original else { return original }
        let editable = PageLayers.editableObjectIDs(in: original, layerID: activeLayerID)
        let mayInsert = PageLayers.editable(activeLayerID, page: original)
        let owner: UUID? = activeLayerID == original.id ? nil : activeLayerID
        func scoped<T: Identifiable>(_ previous: [T], _ incoming: [T], owner key: WritableKeyPath<T, UUID?>,
                                     allowed: Set<UUID>, stamping: ((inout T) -> Void)? = nil) -> [T] where T.ID == UUID {
            let existing = Set(previous.map(\.id))
            let replacements = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            var values: [T] = []
            for value in previous {
                guard allowed.contains(value.id) else { values.append(value); continue }
                if var replacement = replacements[value.id] {
                    replacement[keyPath: key] = value[keyPath: key]
                    stamping?(&replacement)
                    values.append(replacement)
                }
            }
            if mayInsert {
                for var value in incoming where !existing.contains(value.id) {
                    value[keyPath: key] = owner; stamping?(&value); values.append(value)
                }
            }
            return values
        }
        func optional<T>(_ values: [T], previous: [T]?, incoming: [T]?) -> [T]? {
            previous == nil && incoming == nil && values.isEmpty ? nil : values
        }
        var result = proposed
        result.layers = original.layers
        result.texts = scoped(original.texts, proposed.texts, owner: \.layerID, allowed: editable)
        result.images = scoped(original.images, proposed.images, owner: \.layerID, allowed: editable)
        let shapes = scoped(original.shapes ?? [], proposed.shapes ?? [], owner: \.layerID, allowed: editable) {
            $0.audioAnchor?.layerID = owner
        }
        result.shapes = optional(shapes, previous: original.shapes, incoming: proposed.shapes)
        let connectors = scoped(original.connectors ?? [], proposed.connectors ?? [], owner: \.layerID, allowed: editable) {
            $0.audioAnchor?.layerID = owner
        }
        result.connectors = optional(connectors, previous: original.connectors, incoming: proposed.connectors)
        let tapes = scoped(original.tapes ?? [], proposed.tapes ?? [], owner: \.layerID, allowed: editable)
        result.tapes = optional(tapes, previous: original.tapes, incoming: proposed.tapes)
        let markupIDs = PageLayers.editableMarkupIDs(in: original, layerID: activeLayerID)
        let marks = scoped(original.pdfMarkups ?? [], proposed.pdfMarkups ?? [], owner: \.layerID, allowed: markupIDs)
        result.pdfMarkups = optional(marks, previous: original.pdfMarkups, incoming: proposed.pdfMarkups)
        let anchorIDs = Set(original.anchors.filter { PageLayers.canonical($0.layerID, page: original) == activeLayerID && mayInsert }.map(\.id))
        result.anchors = scoped(original.anchors, proposed.anchors, owner: \.layerID, allowed: anchorIDs)
        // A lock may be removed explicitly on this owner, but cannot be used
        // to unlock an object on a different owner as a side effect of a tool.
        let owned = PageLayers.ownedObjectIDs(in: result, layerID: activeLayerID)
        let all = Set(result.objectIDs), oldLocked = Set(original.lockedObjects ?? [])
        let locked = mayInsert ? oldLocked.subtracting(owned).union(Set(proposed.lockedObjects ?? []).intersection(owned)).intersection(all) : oldLocked.intersection(all)
        result.lockedObjects = locked.isEmpty ? nil : locked.sorted { $0.uuidString < $1.uuidString }
        let newIDs = all.subtracting(original.objectIDs)
        let mutable = editable.union(newIDs)
        let above = Set(original.aboveInkObjects ?? []).subtracting(mutable)
            .union(Set(proposed.aboveInkObjects ?? []).intersection(mutable)).intersection(all)
        result.aboveInkObjects = above.isEmpty ? nil : above.sorted { $0.uuidString < $1.uuidString }
        // Keep the internal order of every untouched owner. Layer order, not
        // this interleaving, defines the final composition between owners.
        if proposed.objectOrder != original.objectOrder {
            let desired = proposed.orderedObjectIDs.filter { all.contains($0) && mutable.contains($0) }
            var cursor = 0, ordered: [UUID] = []
            for id in original.orderedObjectIDs where all.contains(id) {
                if !mutable.contains(id) { ordered.append(id) }
                else if cursor < desired.count { ordered.append(desired[cursor]); cursor += 1 }
            }
            ordered.append(contentsOf: desired.dropFirst(cursor)); result.objectOrder = ordered
        } else { result.objectOrder = original.objectOrder }
        result.pruneObjectReferences()
        return result
    }
}
