import Foundation

/// A read-only composition plan shared by the future viewport compositor and
/// sequential vector export. It carries identities and immutable references,
/// never native drawing archives, PDF decoders or full-page bitmap allocations.
public struct LayerRenderGroup: Equatable, Sendable {
    public let layer: PageLayer
    public let drawingFile: String?
    public let previousDrawingFile: String?
    public let isActive: Bool
    public let ordinaryMarkupIDs: [UUID]
    public let underObjectIDs: [UUID]
    public let wordMarkupIDs: [UUID]
    public let underMarkerIDs: [UUID]
    public let aboveObjectIDs: [UUID]
    public let tapeIDs: [UUID]
    public var opacity: Double { layer.opacity ?? 1 }
    public func restricting(objects: Set<UUID>, markups: Set<UUID>) -> Self {
        Self(layer: layer, drawingFile: drawingFile, previousDrawingFile: previousDrawingFile, isActive: isActive,
            ordinaryMarkupIDs: ordinaryMarkupIDs.filter(markups.contains), underObjectIDs: underObjectIDs.filter(objects.contains),
            wordMarkupIDs: wordMarkupIDs.filter(markups.contains), underMarkerIDs: underMarkerIDs.filter(objects.contains),
            aboveObjectIDs: aboveObjectIDs.filter(objects.contains), tapeIDs: tapeIDs.filter(objects.contains))
    }
}

public enum LayerRenderPlan {
    /// Groups are bottom to top. Every group's stages are: ordinary PDF
    /// annotations, under-ink objects, word/rectangle markers, native ink,
    /// foreground objects, study tapes. Individual locks never hide content.
    /// Group opacity is deliberately not multiplied into primitive colors here.
    public static func make(page: PageSnapshot, selection: LayerExportSelection = .visible, activeLayerID: UUID? = nil) throws -> [LayerRenderGroup] {
        try PageValidation.validate(page)
        let ordered = page.orderedObjectIDs
        let above = Set(page.aboveInkObjects ?? [])
        let tapes = Set((page.tapes ?? []).map(\.id))
        let markers = Set((page.shapes ?? []).filter { $0.rectangularMarker == true }.map(\.id))
        let markups = page.pdfMarkups ?? []
        return selection.layers(in: page).map { layer in
            let owned = PageLayers.ownedObjectIDs(in: page, layerID: layer.id)
            let objects = ordered.filter(owned.contains)
            let marks = markups.filter { PageLayers.canonical($0.layerID, page: page) == layer.id }
            return LayerRenderGroup(layer: layer,
                drawingFile: PageLayers.drawingFile(for: layer.id, in: page),
                previousDrawingFile: PageLayers.previousDrawingFile(for: layer.id, in: page),
                isActive: layer.id == activeLayerID,
                ordinaryMarkupIDs: marks.filter { $0.wordHighlight != true }.map(\.id),
                underObjectIDs: objects.filter { !above.contains($0) && !markers.contains($0) && !tapes.contains($0) },
                wordMarkupIDs: marks.filter { $0.wordHighlight == true }.map(\.id),
                underMarkerIDs: objects.filter { !above.contains($0) && markers.contains($0) },
                aboveObjectIDs: objects.filter { above.contains($0) && !tapes.contains($0) },
                tapeIDs: objects.filter(tapes.contains))
        }
    }
}
