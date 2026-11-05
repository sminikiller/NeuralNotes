import Foundation
import PencilKit
import NeuralNotesCore

/// These value-only PencilKit operations run on a worker, never on a canvas.
enum TypeDeletionInk {
    struct Result: Sendable {
        let counts: [PageDeletionKind: Int]
        let drawing: Data?
        let anchors: [StrokeAnchor]
        let composition: LayerComposition?
        init(counts: [PageDeletionKind: Int], drawing: Data?, anchors: [StrokeAnchor], composition: LayerComposition? = nil) {
            self.counts = counts; self.drawing = drawing; self.anchors = anchors; self.composition = composition
        }
    }
    static func process(_ data: Data?, page: PageSnapshot, removing kinds: Set<PageDeletionKind> = [], layerID: UUID? = nil, includeMetadata: Bool = true) throws -> Result {
        let original = try data.map { try PKDrawing(data: $0) } ?? PKDrawing()
        var counts = includeMetadata ? PageDeletion.metadataCounts(in: page) : [:]
        let owner = layerID ?? page.id
        var kept: [Int] = []
        for (index, stroke) in original.strokes.enumerated() {
            let kind: PageDeletionKind = stroke.ink.inkType == .marker ? .marker : .pen
            counts[kind, default: 0] += 1
            if !kinds.contains(kind) { kept.append(index) }
        }
        guard kept.count != original.strokes.count else { return Result(counts: counts, drawing: nil, anchors: page.anchors) }
        let drawing = PKDrawing(strokes: kept.map { original.strokes[$0] })
        let oldKeys = EditorInkSignatures.make(original), newKeys = EditorInkSignatures.make(drawing)
        if page.layers != nil {
            let anchors = LayerStrokeTimeline.replacing(anchors: page.anchors, oldSignatures: oldKeys, newSignatures: newKeys,
                retainedOriginalIndices: kept, pageID: page.id, layerID: owner)
            let composition = page.layers?.first(where: { $0.id == owner })?.composition?.replacingStrokes(old: oldKeys, new: newKeys, retainedIndices: kept)
            return Result(counts: counts, drawing: drawing.dataRepresentation(), anchors: anchors, composition: composition)
        }
        let anchors = Dictionary(grouping: page.anchors, by: \.signature)
        let retained = kept.enumerated().flatMap { offset, index in
            (anchors[oldKeys[index]] ?? []).map { anchor in
                var value = anchor; value.signature = newKeys[offset]; return value
            }
        }
        return Result(counts: counts, drawing: drawing.dataRepresentation(), anchors: retained)
    }
}

struct TypeDeletionPreview: Sendable {
    let order: [UUID]
    let pageIDs: [UUID]
    let revisions: [UUID: Int]
    let counts: [PageDeletionKind: Int]
    let requiresBackup: Bool
    func count(_ kinds: Set<PageDeletionKind>) -> Int { kinds.reduce(0) { $0 + counts[$1, default: 0] } }
}

enum TypeDeletionFailure: LocalizedError {
    case unavailable, backupRequired, changed
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Termina il tratto, la registrazione o la compressione prima di eliminare elementi."
        case .backupRequired: return "Il backup preventivo non è stato creato. Nessun elemento è stato eliminato."
        case .changed: return "Le pagine sono cambiate. Ricalcola il conteggio prima di confermare."
        }
    }
}
