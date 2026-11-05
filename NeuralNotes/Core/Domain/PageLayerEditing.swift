import Foundation

public enum PageLayerFailure: LocalizedError {
    case missing, limit, invalidName, invalidOpacity, baseLayer, locked, drawingCopyRequired
    public var errorDescription: String? {
        switch self {
        case .missing: return "Livello non trovato."
        case .limit: return "Una pagina può contenere al massimo 16 livelli."
        case .invalidName: return "Il nome del livello deve contenere da 1 a 60 caratteri."
        case .invalidOpacity: return "L’opacità deve essere compresa tra 0 e 100%."
        case .baseLayer: return "Il livello Base si può svuotare; non viene eliminato dalla pagina."
        case .locked: return "Sblocca il livello prima di eliminarlo."
        case .drawingCopyRequired: return "Copia prima il disegno del livello in un nuovo file."
        }
    }
}

/// Pure header transformations. The editor must capture file-backed history and
/// commit through DocumentWorkspace before presenting these operations as saved.
/// Drawing duplication is prepared as a new immutable file, never shared within
/// one page; no native vector payload is decoded by this metadata layer.
public enum PageLayerEditing {
    public static func adding(to input: PageSnapshot, name: String) throws -> (page: PageSnapshot, layerID: UUID) {
        try PageValidation.validate(input)
        var layers = PageLayers.ordered(in: input)
        guard layers.count < PageLayers.maximumCount else { throw PageLayerFailure.limit }
        let layer = PageLayer(name: try validName(name)); layers.append(layer)
        var page = input; page.layers = layers; return (page, layer.id)
    }
    public static func renaming(_ id: UUID, to name: String, in input: PageSnapshot) throws -> PageSnapshot {
        let name = try validName(name)
        return try updating(id, in: input) { $0.name = name }
    }
    public static func visibility(_ id: UUID, visible: Bool, in input: PageSnapshot) throws -> PageSnapshot {
        try updating(id, in: input) { $0.isVisible = visible }
    }
    public static func lock(_ id: UUID, locked: Bool, in input: PageSnapshot) throws -> PageSnapshot {
        try updating(id, in: input) { $0.isLocked = locked }
    }
    public static func opacity(_ id: UUID, value: Double, in input: PageSnapshot) throws -> PageSnapshot {
        guard value.isFinite, (0...1).contains(value) else { throw PageLayerFailure.invalidOpacity }
        return try updating(id, in: input) { $0.opacity = value == 1 ? nil : value }
    }
    public static func reordering(_ ids: [UUID], in input: PageSnapshot) throws -> PageSnapshot {
        try PageValidation.validate(input)
        let layers = PageLayers.ordered(in: input), map = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        guard ids.count == layers.count, Set(ids).count == ids.count, Set(ids) == Set(map.keys) else { throw PageLayerFailure.missing }
        var page = input; page.layers = ids.compactMap { map[$0] }; return page
    }
    public static func removing(_ id: UUID, in input: PageSnapshot) throws -> PageSnapshot {
        try PageValidation.validate(input)
        guard id != input.id else { throw PageLayerFailure.baseLayer }
        var page = try clearing(id, in: input)
        page.layers?.removeAll { $0.id == id }
        try PageValidation.validate(page); return page
    }
    /// Clearing Base retains the PDF, paper and the Base identity. File-backed
    /// undo must own its immutable references before this header is committed.
    public static func clearing(_ id: UUID, in input: PageSnapshot) throws -> PageSnapshot {
        try PageValidation.validate(input)
        guard let layer = PageLayers.ordered(in: input).first(where: { $0.id == id }) else { throw PageLayerFailure.missing }
        guard !layer.isLocked else { throw PageLayerFailure.locked }
        var page = input
        func owns(_ owner: UUID?) -> Bool { PageLayers.canonical(owner, page: input) == id }
        if id == input.id { page.drawingFile = nil; page.previousDrawingFile = nil }
        else if let index = page.layers?.firstIndex(where: { $0.id == id }) {
            page.layers?[index].drawingFile = nil; page.layers?[index].previousDrawingFile = nil
        }
        page.texts.removeAll { owns($0.layerID) }; page.images.removeAll { owns($0.layerID) }
        page.shapes = page.shapes?.filter { !owns($0.layerID) }; page.connectors = page.connectors?.filter { !owns($0.layerID) }
        page.tapes = page.tapes?.filter { !owns($0.layerID) }; page.pdfMarkups = page.pdfMarkups?.filter { !owns($0.layerID) }
        page.anchors.removeAll { owns($0.layerID) }; page.pruneObjectReferences()
        try PageValidation.validate(page); return page
    }
    public static func duplicating(_ id: UUID, in input: PageSnapshot, name: String, drawingCopy: String?) throws -> (page: PageSnapshot, layerID: UUID) {
        try PageValidation.validate(input)
        let source = try PageLayers.ordered(in: input).first(where: { $0.id == id }).unwrapLayer()
        let added = try adding(to: input, name: name), target = added.layerID
        if PageLayers.drawingFile(for: id, in: input) != nil {
            guard let drawingCopy, !input.allDrawingFiles.contains(drawingCopy) else { throw PageLayerFailure.drawingCopyRequired }
        } else if drawingCopy != nil { throw PageLayerFailure.drawingCopyRequired }
        var page = added.page
        guard let index = page.layers?.firstIndex(where: { $0.id == target }) else { throw PageLayerFailure.missing }
        page.layers?[index].isVisible = source.isVisible; page.layers?[index].opacity = source.opacity
        page.layers?[index].drawingFile = drawingCopy
        func owns(_ owner: UUID?) -> Bool { (owner ?? input.id) == id }
        func anchor(_ input: StrokeAnchor?) -> StrokeAnchor? {
            guard var value = input else { return nil }; value.id = UUID(); value.layerID = target; return value
        }
        var map: [UUID: UUID] = [:]
        for var value in input.texts where owns(value.layerID) {
            let old = value.id; value.id = UUID(); value.layerID = target; map[old] = value.id; page.texts.append(value)
        }
        for var value in input.images where owns(value.layerID) {
            let old = value.id; value.id = UUID(); value.layerID = target; map[old] = value.id; page.images.append(value)
        }
        for var value in input.shapes ?? [] where owns(value.layerID) {
            let old = value.id; value.id = UUID(); value.layerID = target; map[old] = value.id; value.audioAnchor = anchor(value.audioAnchor)
            if page.shapes == nil { page.shapes = [] }; page.shapes?.append(value)
        }
        for var value in input.tapes ?? [] where owns(value.layerID) {
            let old = value.id; value.id = UUID(); value.layerID = target; map[old] = value.id
            if page.tapes == nil { page.tapes = [] }; page.tapes?.append(value)
        }
        // Targets within the copied group follow their new IDs. External targets
        // stay connected to the existing object, rather than becoming dangling.
        for var value in input.connectors ?? [] where owns(value.layerID) {
            let old = value.id; value.id = UUID(); value.layerID = target; map[old] = value.id; value.audioAnchor = anchor(value.audioAnchor)
            if let from = value.from.objectID, let replacement = map[from] { value.from.objectID = replacement }
            if let to = value.to.objectID, let replacement = map[to] { value.to.objectID = replacement }
            if page.connectors == nil { page.connectors = [] }; page.connectors?.append(value)
        }
        for var value in input.pdfMarkups ?? [] where owns(value.layerID) {
            value.id = UUID(); value.layerID = target
            if page.pdfMarkups == nil { page.pdfMarkups = [] }; page.pdfMarkups?.append(value)
        }
        for value in input.anchors where owns(value.layerID) { if let copied = anchor(value) { page.anchors.append(copied) } }
        page.objectOrder = input.orderedObjectIDs + input.orderedObjectIDs.compactMap { map[$0] }
        if let values = input.aboveInkObjects { page.aboveInkObjects = values + values.compactMap { map[$0] } }
        if let values = input.lockedObjects { page.lockedObjects = values + values.compactMap { map[$0] } }
        // Place the copy immediately above its original, preserving all other order.
        var layers = page.layers ?? []
        let copy = layers.removeLast()
        guard let position = layers.firstIndex(where: { $0.id == id }) else { throw PageLayerFailure.missing }
        layers.insert(copy, at: position + 1); page.layers = layers
        try PageValidation.validate(page); return (page, target)
    }
    private static func updating(_ id: UUID, in input: PageSnapshot, edit: (inout PageLayer) -> Void) throws -> PageSnapshot {
        try PageValidation.validate(input)
        var page = input, layers = PageLayers.ordered(in: input)
        guard let index = layers.firstIndex(where: { $0.id == id }) else { throw PageLayerFailure.missing }
        edit(&layers[index]); page.layers = layers; try PageValidation.validate(page); return page
    }
    private static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw PageLayerFailure.invalidName }; return name
    }
}

private extension Optional where Wrapped == PageLayer {
    func unwrapLayer() throws -> PageLayer { guard let self else { throw PageLayerFailure.missing }; return self }
}
