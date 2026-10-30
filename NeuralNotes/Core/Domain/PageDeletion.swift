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
        case .shapes: values = (page.shapes ?? []).map(\.id)
        case .connectors: values = (page.connectors ?? []).map(\.id)
        case .text: values = page.texts.filter { $0.lensNote == nil }.map(\.id)
        case .images: values = page.images.map(\.id)
        case .tapes: values = (page.tapes ?? []).map(\.id)
        case .lensNotes: values = page.texts.filter { $0.lensNote != nil }.map(\.id)
        case .pen, .marker, .audioLinks: values = []
        }
        return Set(values).subtracting(page.lockedObjects ?? [])
    }
    public static func metadataCounts(in page: PageSnapshot) -> [PageDeletionKind: Int] {
        var counts = Dictionary(uniqueKeysWithValues: PageDeletionKind.allCases.map { ($0, objectIDs(in: page, kind: $0).count) })
        let locked = Set(page.lockedObjects ?? [])
        let shapes = (page.shapes ?? []).filter { !locked.contains($0.id) && $0.audioAnchor != nil }.count
        let edges = (page.connectors ?? []).filter { !locked.contains($0.id) && $0.audioAnchor != nil }.count
        counts[.audioLinks] = page.anchors.count + shapes + edges
        // Existing PDF selection markup belongs to the same visible categories.
        counts[.marker] = (page.pdfMarkups ?? []).filter { $0.kind == .highlight }.count
        counts[.pen] = (page.pdfMarkups ?? []).filter { $0.kind == .underline }.count
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
        if kinds.contains(.marker) { page.pdfMarkups?.removeAll { $0.kind == .highlight } }
        if kinds.contains(.pen) { page.pdfMarkups?.removeAll { $0.kind == .underline } }
        if !ids.isEmpty || kinds.contains(.pen) || kinds.contains(.marker) {
            // The old visual OCR must not make deleted content searchable.
            page.recognizedText = ""
        }
        if kinds.contains(.audioLinks) {
            page.anchors = []
            let locked = Set(page.lockedObjects ?? [])
            if var shapes = page.shapes {
                for i in shapes.indices where !locked.contains(shapes[i].id) { shapes[i].audioAnchor = nil }
                page.shapes = shapes
            }
            if var edges = page.connectors {
                for i in edges.indices where !locked.contains(edges[i].id) { edges[i].audioAnchor = nil }
                page.connectors = edges
            }
        }
        page.pruneObjectReferences()
        return page
    }
}
