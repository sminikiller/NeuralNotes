import Foundation

/// Native paths are not altered to manufacture a unique audio signature. The
/// owner and occurrence distinguish exact copies, including after a merge.
/// Nil occurrence keeps existing documents' "all matching signatures" behavior.
public enum LayerStrokeTimeline {
    /// A partial eraser may change native signatures or remove occurrences.
    /// Retained indices identify the original strokes without touching their
    /// paths, masks or pressure. Anchors belonging to other owners stay exact.
    public static func replacing(anchors: [StrokeAnchor], oldSignatures: [String], newSignatures: [String], retainedOriginalIndices: [Int], pageID: UUID, layerID: UUID?) -> [StrokeAnchor] {
        guard newSignatures.count == retainedOriginalIndices.count,
              Set(retainedOriginalIndices).count == retainedOriginalIndices.count,
              retainedOriginalIndices.allSatisfy(oldSignatures.indices.contains) else { return anchors }
        let owner = layerID ?? pageID
        let oldKeys = keys(signatures: oldSignatures, pageID: pageID, layerID: owner)
        let newKeys = keys(signatures: newSignatures, pageID: pageID, layerID: owner)
        let positions = Dictionary(grouping: oldKeys.indices, by: { oldKeys[$0].signature })
        let retained = Dictionary(uniqueKeysWithValues: retainedOriginalIndices.enumerated().map { ($0.element, $0.offset) })
        let newCounts = newSignatures.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var result: [StrokeAnchor] = []
        for anchor in anchors {
            guard (anchor.layerID ?? pageID) == owner else { result.append(anchor); continue }
            let old = positions[anchor.signature] ?? []
            let matched = old.filter { anchor.strokeOccurrence == nil || oldKeys[$0].occurrence == anchor.strokeOccurrence }
            if matched.isEmpty {
                var orphan = anchor
                orphan.strokeOccurrence = newCounts[anchor.signature, default: 0] + max(0, (anchor.strokeOccurrence ?? old.count) - old.count)
                result.append(orphan); continue
            }
            let survivors = matched.compactMap { retained[$0] }
            for (copyIndex, newIndex) in survivors.enumerated() {
                var copy = anchor
                if copyIndex > 0 { copy.id = UUID() }
                copy.signature = newKeys[newIndex].signature; copy.strokeOccurrence = newKeys[newIndex].occurrence
                result.append(copy)
            }
        }
        return result
    }
    public static func keys(signatures: [String], pageID: UUID, layerID: UUID?) -> [LayerInkSignature] {
        var counts: [String: Int] = [:]
        return signatures.map { signature in
            let occurrence = counts[signature, default: 0]; counts[signature] = occurrence + 1
            return LayerInkSignature(layerID: layerID, pageID: pageID, signature: signature, occurrence: occurrence)
        }
    }
    public static func visible(signatures: [String], anchors: [StrokeAnchor], pageID: UUID, layerID: UUID?, sessionID: UUID, seconds: Double) -> [Int] {
        guard seconds.isFinite else { return [] }
        let keys = keys(signatures: signatures, pageID: pageID, layerID: layerID)
        let timeline = times(anchors: anchors, pageID: pageID, sessionID: sessionID)
        return keys.indices.filter { index in
            let key = keys[index]
            let wildcard = LayerInkSignature(layerID: key.layerID, pageID: pageID, signature: key.signature)
            return (timeline[key] ?? timeline[wildcard]).map { $0 <= seconds } ?? true
        }
    }
    public static func current(signatures: [String], anchors: [StrokeAnchor], pageID: UUID, layerID: UUID?, sessionID: UUID, seconds: Double) -> [Int] {
        guard seconds.isFinite else { return [] }
        let keys = keys(signatures: signatures, pageID: pageID, layerID: layerID)
        let timeline = times(anchors: anchors, pageID: pageID, sessionID: sessionID)
        var candidates: [(Int, Double)] = []
        for index in keys.indices {
            let key = keys[index], wildcard = LayerInkSignature(layerID: keys[index].layerID, pageID: pageID, signature: keys[index].signature)
            if let time = timeline[key] ?? timeline[wildcard], time <= seconds, seconds - time <= 2 { candidates.append((index, time)) }
        }
        guard let latest = candidates.map({ $0.1 }).max() else { return [] }
        return candidates.filter { abs($0.1 - latest) <= 0.05 }.map { $0.0 }
    }
    /// Target paths precede source paths in the merged native drawing. Rebase
    /// only the relevant owners, keeping every timestamp and original signature.
    /// A legacy wildcard is expanded if a signature occurs more than once.
    public static func rebasingForMerge(anchors: [StrokeAnchor], targetSignatures: [String], sourceSignatures: [String], pageID: UUID, targetID: UUID, sourceID: UUID) -> [StrokeAnchor] {
        guard targetID != sourceID else { return anchors }
        let targetCounts = targetSignatures.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let sourceCounts = sourceSignatures.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var result: [StrokeAnchor] = []
        for anchor in anchors {
            let owner = anchor.layerID ?? pageID
            guard owner == targetID || owner == sourceID else { result.append(anchor); continue }
            let counts = owner == sourceID ? sourceCounts : targetCounts
            let offset = owner == sourceID ? targetCounts[anchor.signature, default: 0] : 0
            let occurrences: [Int?]
            if let ordinal = anchor.strokeOccurrence { occurrences = [ordinal] }
            else if let count = counts[anchor.signature], count > 0 { occurrences = (0..<count).map { Optional($0) } }
            else { occurrences = [nil] } // Preserve an existing orphan anchor.
            for (index, ordinal) in occurrences.enumerated() {
                var copy = anchor
                if index > 0 { copy.id = UUID() }
                copy.layerID = targetID == pageID ? nil : targetID
                let ownCount = counts[anchor.signature, default: 0]
                let total = targetCounts[anchor.signature, default: 0] + sourceCounts[anchor.signature, default: 0]
                if let ordinal, ordinal < ownCount { copy.strokeOccurrence = ordinal + offset }
                else {
                    // An orphan must not attach to a newly merged stroke with
                    // the same native signature. Retain its time off the end.
                    copy.strokeOccurrence = total + max(0, (ordinal ?? ownCount) - ownCount)
                }
                result.append(copy)
            }
        }
        return result
    }
    private static func times(anchors: [StrokeAnchor], pageID: UUID, sessionID: UUID) -> [LayerInkSignature: Double] {
        var result: [LayerInkSignature: Double] = [:]
        for anchor in anchors where anchor.audioSessionID == sessionID && anchor.seconds.isFinite && anchor.seconds >= 0 {
            let key = LayerInkSignature(layerID: anchor.layerID, pageID: pageID, signature: anchor.signature, occurrence: anchor.strokeOccurrence)
            result[key] = min(result[key] ?? anchor.seconds, anchor.seconds)
        }
        return result
    }
}
