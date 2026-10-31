import Foundation

public enum EraserTarget: String, Codable, CaseIterable, Sendable {
    case all, marker, pen, shapes, text, images
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .marker }
    public var title: String {
        switch self {
        case .all: return "Tutto"
        case .marker: return "Solo evidenziatore"
        case .pen: return "Solo penna"
        case .shapes: return "Solo forme e connettori"
        case .text: return "Solo testo e post-it"
        case .images: return "Solo immagini"
        }
    }
    public var includesInk: Bool { self == .all || self == .pen || self == .marker }
    public var includesObjects: Bool { self == .all || self == .shapes || self == .text || self == .images }
}

/// One spatial index per gesture. Large extents occupy an overflow list; a
/// large query scans the short box table instead of allocating unbounded cells.
public struct EraserSpatialIndex: Sendable {
    private struct Cell: Hashable, Sendable { let x: Int; let y: Int }
    private var cells: [Cell: Set<UUID>] = [:]
    private var large = Set<UUID>()
    private var boxes: [UUID: SnapRect]
    public init(boxes: [UUID: SnapRect]) {
        self.boxes = boxes.filter { $0.value.valid }
        for (id, box) in self.boxes {
            let x0 = Int(floor(box.x / 64)), x1 = Int(floor(box.maxX / 64))
            let y0 = Int(floor(box.y / 64)), y1 = Int(floor(box.maxY / 64))
            if (x1 - x0 + 1) * (y1 - y0 + 1) > 256 { large.insert(id); continue }
            for x in x0...x1 { for y in y0...y1 { cells[Cell(x: x, y: y), default: []].insert(id) } }
        }
    }
    public func candidates(in rect: SnapRect) -> Set<UUID> {
        guard rect.valid else { return [] }
        let x0 = Int(floor(rect.x / 64)), x1 = Int(floor(rect.maxX / 64))
        let y0 = Int(floor(rect.y / 64)), y1 = Int(floor(rect.maxY / 64))
        var possible = large
        if (x1 - x0 + 1) * (y1 - y0 + 1) > 4096 { possible = Set(boxes.keys) }
        else { for x in x0...x1 { for y in y0...y1 { possible.formUnion(cells[Cell(x: x, y: y)] ?? []) } } }
        return possible.filter { id in
            guard let box = boxes[id] else { return false }
            return box.x <= rect.maxX && box.maxX >= rect.x && box.y <= rect.maxY && box.maxY >= rect.y
        }
    }
}
