import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func scopedSelectionIDs(in page: PageSnapshot, includingConnectors: Bool = true) -> Set<UUID> {
        let ids = includingConnectors ? page.includingInternalConnectors(selectedIDs) : selectedIDs
        guard page.layers != nil else { return ids }
        return ids.intersection(PageLayers.editableObjectIDs(in: page, layerID: drawingLayerID ?? page.id))
    }
}

extension PageSnapshot {
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
