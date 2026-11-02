import Foundation

public struct PageLayer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var opacity: Double?
    public var drawingFile: String?
    public var previousDrawingFile: String?
    public init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id; self.name = name; self.isVisible = isVisible; self.isLocked = isLocked
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60 &&
        opacity.map { $0.isFinite && (0...1).contains($0) } != false
    }
}

/// Layer storage/selection contract only. The active canvas adapter must opt in
/// after transactional save/recovery and render order are implemented.
public enum PageLayers {
    public static let maximumCount = 16
    public static func ordered(in page: PageSnapshot) -> [PageLayer] {
        page.layers ?? [PageLayer(id: page.id, name: "Base")]
    }
    public static func canonical(_ id: UUID?, page: PageSnapshot) -> UUID { id ?? page.id }
    public static func editable(_ id: UUID, page: PageSnapshot) -> Bool {
        ordered(in: page).contains { $0.id == id && $0.isVisible && !$0.isLocked && ($0.opacity ?? 1) > 0 }
    }
    public static func validate(_ page: PageSnapshot) throws {
        let ordered = ordered(in: page), ids = Set(ordered.map(\.id))
        guard (1...maximumCount).contains(ordered.count), ids.count == ordered.count,
              ordered.allSatisfy(\.isValid), ordered.filter({ $0.id == page.id }).count == 1 else { throw LibraryFailure.corruptDocument }
        var currentFiles = Set<String>()
        for layer in ordered {
            if layer.id == page.id {
                guard layer.drawingFile == nil, layer.previousDrawingFile == nil else { throw LibraryFailure.corruptDocument }
            } else {
                for file in [layer.drawingFile, layer.previousDrawingFile].compactMap({ $0 }) {
                    guard validDrawingPath(file) else { throw LibraryFailure.corruptDocument }
                }
                if let file = layer.drawingFile, !currentFiles.insert(file).inserted { throw LibraryFailure.corruptDocument }
            }
        }
        if let file = page.drawingFile, currentFiles.contains(file) { throw LibraryFailure.corruptDocument }
        var ownership: [UUID] = page.texts.compactMap(\.layerID)
        ownership.append(contentsOf: page.images.compactMap(\.layerID))
        ownership.append(contentsOf: (page.shapes ?? []).compactMap(\.layerID))
        ownership.append(contentsOf: (page.connectors ?? []).compactMap(\.layerID))
        ownership.append(contentsOf: (page.tapes ?? []).compactMap(\.layerID))
        ownership.append(contentsOf: (page.pdfMarkups ?? []).compactMap(\.layerID))
        guard ownership.allSatisfy(ids.contains), page.anchors.compactMap(\.layerID).allSatisfy(ids.contains) else { throw LibraryFailure.corruptDocument }
        let embedded = (page.shapes ?? []).compactMap(\.audioAnchor) + (page.connectors ?? []).compactMap(\.audioAnchor)
        guard embedded.compactMap(\.layerID).allSatisfy(ids.contains) else { throw LibraryFailure.corruptDocument }
    }
    public static func drawingFile(for id: UUID, in page: PageSnapshot) -> String? {
        id == page.id ? page.drawingFile : page.layers?.first(where: { $0.id == id })?.drawingFile
    }
    public static func ownedObjectIDs(in page: PageSnapshot, layerID: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        for value in page.texts where canonical(value.layerID, page: page) == layerID { result.insert(value.id) }
        for value in page.images where canonical(value.layerID, page: page) == layerID { result.insert(value.id) }
        for value in page.shapes ?? [] where canonical(value.layerID, page: page) == layerID { result.insert(value.id) }
        for value in page.connectors ?? [] where canonical(value.layerID, page: page) == layerID { result.insert(value.id) }
        for value in page.tapes ?? [] where canonical(value.layerID, page: page) == layerID { result.insert(value.id) }
        return result
    }
    public static func editableObjectIDs(in page: PageSnapshot, layerID: UUID) -> Set<UUID> {
        guard editable(layerID, page: page) else { return [] }
        return ownedObjectIDs(in: page, layerID: layerID).subtracting(page.lockedObjects ?? [])
    }
    public static func editableMarkupIDs(in page: PageSnapshot, layerID: UUID) -> Set<UUID> {
        guard editable(layerID, page: page) else { return [] }
        return Set((page.pdfMarkups ?? []).filter { canonical($0.layerID, page: page) == layerID }.map(\.id))
    }
    private static func validDrawingPath(_ file: String) -> Bool {
        let parts = file.split(separator: "/", omittingEmptySubsequences: false)
        return file.utf8.count <= 1024 && file.hasPrefix("drawings/") && file.hasSuffix(".drawing") && !file.contains("\\") && !file.contains(":") &&
            parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }
    }
}

public extension PageSnapshot {
    var allDrawingFiles: [String] {
        [drawingFile, previousDrawingFile].compactMap { $0 } + (layers ?? []).flatMap { [$0.drawingFile, $0.previousDrawingFile].compactMap { $0 } }
    }
    /// Canonical reachability used by validation, cleanup and recovery. Hidden
    /// layers and their previous revisions are every bit as live as visible ink.
    var mediaFiles: Set<String> { Set(allDrawingFiles + [pdfFile].compactMap { $0 } + images.map(\.file)) }
    /// Base live ink is captured separately by PageEditSnapshot. Inactive ink
    /// is immutable media and must be retained outside the source package too.
    var snapshotMediaFiles: Set<String> {
        Set(images.map(\.file) + (layers ?? []).flatMap { [$0.drawingFile, $0.previousDrawingFile].compactMap { $0 } })
    }
    mutating func remapMedia(_ map: (String) throws -> String) rethrows {
        drawingFile = try drawingFile.map(map); previousDrawingFile = try previousDrawingFile.map(map); pdfFile = try pdfFile.map(map)
        for i in images.indices { images[i].file = try map(images[i].file) }
        if var values = layers {
            for i in values.indices { values[i].drawingFile = try values[i].drawingFile.map(map); values[i].previousDrawingFile = try values[i].previousDrawingFile.map(map) }
            layers = values
        }
    }
    /// Call after changing page.id; nil ownership remains the base. Connectors'
    /// object IDs and page links are handled by the existing object/page clone.
    mutating func renewLayerIDs(from sourcePageID: UUID) {
        guard var values = layers else { return }
        var map: [UUID: UUID] = [sourcePageID: id]
        for i in values.indices { let source = values[i].id; let target = source == sourcePageID ? id : UUID(); map[source] = target; values[i].id = target }
        layers = values
        func owner(_ value: UUID?) -> UUID? { value.flatMap { map[$0] } }
        for i in texts.indices { texts[i].layerID = owner(texts[i].layerID) }
        for i in images.indices { images[i].layerID = owner(images[i].layerID) }
        if var list = shapes { for i in list.indices { list[i].layerID = owner(list[i].layerID); list[i].audioAnchor?.layerID = owner(list[i].audioAnchor?.layerID) }; shapes = list }
        if var list = connectors { for i in list.indices { list[i].layerID = owner(list[i].layerID); list[i].audioAnchor?.layerID = owner(list[i].audioAnchor?.layerID) }; connectors = list }
        if var list = tapes { for i in list.indices { list[i].layerID = owner(list[i].layerID) }; tapes = list }
        if var list = pdfMarkups { for i in list.indices { list[i].layerID = owner(list[i].layerID) }; pdfMarkups = list }
        for i in anchors.indices { anchors[i].layerID = owner(anchors[i].layerID) }
    }
}

/// Export is a read-only selection. Hidden content is retained by native backup
/// independently of the PDF/image choice here; no page flags are rewritten.
public enum LayerExportSelection: Equatable, Sendable {
    case all, visible, selected(Set<UUID>)
    public func layers(in page: PageSnapshot) -> [PageLayer] {
        PageLayers.ordered(in: page).filter { layer in
            switch self { case .all: return true; case .visible: return layer.isVisible; case .selected(let ids): return ids.contains(layer.id) }
        }
    }
}

/// The same native stroke copied to another layer may keep its signature.
/// A composite key prevents anchors on one layer from matching another's ink.
public struct LayerInkSignature: Hashable, Sendable {
    public let layerID: UUID
    public let signature: String
    public init(layerID: UUID?, pageID: UUID, signature: String) { self.layerID = layerID ?? pageID; self.signature = signature }
}
