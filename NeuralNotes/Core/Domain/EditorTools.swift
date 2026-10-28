import Foundation

public struct NormalizedCrop: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = max(0, min(0.99, x)); self.y = max(0, min(0.99, y))
        self.width = max(0.01, min(1 - self.x, width)); self.height = max(0.01, min(1 - self.y, height))
    }
    public static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)
}

public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case ellipse, rectangle, line, arrow, triangle, diamond, polygon, freePolygon, star, arc
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .rectangle
    }
    public var title: String {
        switch self {
        case .ellipse: return "Cerchio"; case .rectangle: return "Rettangolo"; case .line: return "Linea"
        case .arrow: return "Freccia"; case .triangle: return "Triangolo"; case .diamond: return "Rombo"
        case .polygon: return "Poligono"; case .freePolygon: return "Poligono libero"; case .star: return "Stella"; case .arc: return "Arco"
        }
    }
    public var icon: String {
        switch self {
        case .ellipse: return "circle"; case .rectangle: return "rectangle"; case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"; case .triangle: return "triangle"; case .diamond: return "diamond"
        case .polygon: return "hexagon"; case .freePolygon: return "pentagon"; case .star: return "star"; case .arc: return "circle.lefthalf.filled"
        }
    }
    public var isOpen: Bool { self == .line || self == .arrow || self == .arc }
}

public struct ShapeElement: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ShapeKind
    public var x: Double, y: Double, width: Double, height: Double
    public var red: Double, green: Double, blue: Double
    public var lineWidth: Double
    public var start: ShapeEndpoint?
    public var end: ShapeEndpoint?
    public var rotation: Double?
    public var sides: Int?
    public var vertices: [ShapeEndpoint]?
    public var innerRatio: Double?
    public var arcStart: Double?
    public var arcSweep: Double?
    public var fill: InkColor?
    public var fillOpacity: Double?
    public var dash: ShapeDash?
    public var cornerRadius: Double?
    public var arrowHeads: ArrowHeads?
    public var arrowStyle: ArrowStyle?
    public var strokeOpacity: Double?
    public var audioAnchor: StrokeAnchor?
    public init(kind: ShapeKind, x: Double = 80, y: Double = 100, width: Double = 160, height: Double = 160,
                red: Double = 0, green: Double = 0, blue: Double = 0, lineWidth: Double = 3) {
        self.kind = kind; self.x = x; self.y = y; self.width = width; self.height = height
        self.red = red; self.green = green; self.blue = blue; self.lineWidth = lineWidth
    }
}

public struct ShapeEndpoint: Codable, Equatable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public extension ShapeElement {
    static func dragged(kind: ShapeKind, from a: StrokeSample, to b: StrokeSample,
                        color: InkColor, lineWidth: Double) -> ShapeElement? {
        guard [a.x, a.y, b.x, b.y, lineWidth].allSatisfy(\.isFinite), color.isValid,
              hypot(b.x - a.x, b.y - a.y) >= 4, lineWidth > 0, lineWidth <= 200 else { return nil }
        if kind == .arc {
            let diameter = hypot(b.x - a.x, b.y - a.y)
            var arc = ShapeElement(kind: .arc, x: (a.x + b.x - diameter) / 2,
                y: (a.y + b.y - diameter) / 2, width: diameter, height: diameter,
                red: color.red, green: color.green, blue: color.blue, lineWidth: lineWidth)
            arc.arcStart = atan2(a.y - (a.y + b.y) / 2, a.x - (a.x + b.x) / 2)
            arc.arcSweep = .pi
            return arc
        }
        let x = min(a.x, b.x), y = min(a.y, b.y), w = max(1, abs(b.x - a.x)), h = max(1, abs(b.y - a.y))
        var shape = ShapeElement(kind: kind, x: x, y: y, width: w, height: h,
            red: color.red, green: color.green, blue: color.blue, lineWidth: lineWidth)
        shape.start = ShapeEndpoint(x: (a.x - x) / w, y: (a.y - y) / h)
        shape.end = ShapeEndpoint(x: (b.x - x) / w, y: (b.y - y) / h)
        return shape
    }
}

/// Bounded chronological history. Call acknowledge only after the disk/model
/// operation succeeds, so a failed undo can be retried without losing its entry.
public struct EditHistory<Event> {
    public struct Entry { public let event: Event; public let label: String; public let cost: Int }
    private var past: [Entry] = [], future: [Entry] = []
    private let maximumCount: Int, maximumBytes: Int
    public init(maximumCount: Int = 60, maximumBytes: Int = 48 * 1024 * 1024) {
        self.maximumCount = max(1, maximumCount); self.maximumBytes = max(1, maximumBytes)
    }
    public var undo: Entry? { past.last }
    public var redo: Entry? { future.last }
    public mutating func record(_ event: Event, label: String, cost: Int = 0) {
        guard cost <= maximumBytes else { clear(); return }
        future = []; past.append(Entry(event: event, label: label, cost: max(0, cost)))
        while past.count > maximumCount || (past.count > 1 && past.reduce(0, { $0 + $1.cost }) > maximumBytes) { past.removeFirst() }
    }
    public mutating func didUndo() { if let item = past.popLast() { future.append(item) } }
    public mutating func didRedo() { if let item = future.popLast() { past.append(item) } }
    public mutating func clear() { past = []; future = [] }
}

public struct DeskSession: Codable, Equatable, Sendable {
    public var notebookIDs: [UUID]
    public var selectedID: UUID?
    public init(notebookIDs: [UUID], selectedID: UUID?) { self.notebookIDs = notebookIDs; self.selectedID = selectedID }
    public func available(in ids: Set<UUID>) -> DeskSession {
        var seen = Set<UUID>()
        let valid = Array(notebookIDs.filter { ids.contains($0) && seen.insert($0).inserted }.prefix(6))
        return DeskSession(notebookIDs: valid, selectedID: selectedID.flatMap { valid.contains($0) ? $0 : nil } ?? valid.first)
    }
}
