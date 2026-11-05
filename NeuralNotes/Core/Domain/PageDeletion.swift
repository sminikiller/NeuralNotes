import Foundation

public enum PageDeletionKind: String, CaseIterable, Identifiable, Sendable {
    case pen, marker, shapes, connectors, text, images, tapes, lensNotes, audioLinks
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pen: return "Inchiostro della penna"
        case .marker: return "Evidenziatore"
        case .shapes: return "Forme"
        case .connectors: return "Connettori"
        case .text: return "Testo e post-it"
        case .images: return "Immagini"
        case .tapes: return "Nastro di ripasso"
        case .lensNotes: return "Note della Lente"
        case .audioLinks: return "Collegamenti audio"
        }
    }
}

/// Counting and mutation use exactly the same eligible object sets. Native ink
/// is classified by the app adapter; this type never needs PencilKit or UIKit.
public enum PageDeletion {
    public static func objectIDs(in page: PageSnapshot, kind: PageDeletionKind) -> Set<UUID> {
        let values: [UUID]
        switch kind {
        case .shapes: values = (page.shapes ?? []).filter { $0.rectangularMarker != true }.map(\.id)
        case .marker: values = (page.shapes ?? []).filter { $0.rectangularMarker == true }.map(\.id)
        case .connectors: values = (page.connectors ?? []).map(\.id)
        case .text: values = page.texts.filter { $0.lensNote == nil }.map(\.id)
        case .images: values = page.images.map(\.id)
        case .tapes: values = (page.tapes ?? []).map(\.id)
        case .lensNotes: values = page.texts.filter { $0.lensNote != nil }.map(\.id)
        case .pen, .audioLinks: values = []
        }
        let eligible = Set(PageLayers.ordered(in: page).filter { PageLayers.editable($0.id, page: page) }
            .flatMap { PageLayers.ownedObjectIDs(in: page, layerID: $0.id) })
        return Set(values).subtracting(page.lockedObjects ?? []).intersection(eligible)
    }
    public static func metadataCounts(in page: PageSnapshot) -> [PageDeletionKind: Int] {
        var counts = Dictionary(uniqueKeysWithValues: PageDeletionKind.allCases.map { ($0, objectIDs(in: page, kind: $0).count) })
        let shapeIDs = objectIDs(in: page, kind: .shapes).union(objectIDs(in: page, kind: .marker)), edgeIDs = objectIDs(in: page, kind: .connectors)
        let shapes = (page.shapes ?? []).filter { shapeIDs.contains($0.id) && $0.audioAnchor != nil }.count
        let edges = (page.connectors ?? []).filter { edgeIDs.contains($0.id) && $0.audioAnchor != nil }.count
        counts[.audioLinks] = page.anchors.filter { PageLayers.editable($0.layerID ?? page.id, page: page) }.count + shapes + edges
        // Existing PDF selection markup belongs to the same visible categories.
        counts[.marker, default: 0] += (page.pdfMarkups ?? []).filter { $0.kind == .highlight && PageLayers.editable($0.layerID ?? page.id, page: page) }.count
        counts[.pen] = (page.pdfMarkups ?? []).filter { $0.kind == .underline && PageLayers.editable($0.layerID ?? page.id, page: page) }.count
        return counts
    }
    /// Refresh connector fallbacks using the current rendered geometry before
    /// calling this. Removing a target detaches surviving ends in place.
    public static func removing(_ kinds: Set<PageDeletionKind>, from original: PageSnapshot) -> PageSnapshot {
        var page = original
        let ids = kinds.reduce(into: Set<UUID>()) { $0.formUnion(objectIDs(in: original, kind: $1)) }
        page.texts.removeAll { ids.contains($0.id) }
        page.images.removeAll { ids.contains($0.id) }
        page.shapes?.removeAll { ids.contains($0.id) }
        page.connectors?.removeAll { ids.contains($0.id) }
        page.tapes?.removeAll { ids.contains($0.id) }
        if kinds.contains(.marker) { page.pdfMarkups?.removeAll { $0.kind == .highlight && PageLayers.editable($0.layerID ?? original.id, page: original) } }
        if kinds.contains(.pen) { page.pdfMarkups?.removeAll { $0.kind == .underline && PageLayers.editable($0.layerID ?? original.id, page: original) } }
        if !ids.isEmpty || kinds.contains(.pen) || kinds.contains(.marker) {
            // The old visual OCR must not make deleted content searchable.
            page.recognizedText = ""
        }
        if kinds.contains(.audioLinks) {
            page.anchors.removeAll { PageLayers.editable($0.layerID ?? original.id, page: original) }
            let locked = Set(page.lockedObjects ?? [])
            if var shapes = page.shapes {
                for i in shapes.indices where !locked.contains(shapes[i].id) && PageLayers.editable(shapes[i].layerID ?? original.id, page: original) { shapes[i].audioAnchor = nil }
                page.shapes = shapes
            }
            if var edges = page.connectors {
                for i in edges.indices where !locked.contains(edges[i].id) && PageLayers.editable(edges[i].layerID ?? original.id, page: original) { edges[i].audioAnchor = nil }
                page.connectors = edges
            }
        }
        page.pruneObjectReferences()
        return page
    }
}
