import Foundation

public enum ShapeDash: String, CaseIterable, Codable, Sendable {
    case solid, dashed, dotted
    public var title: String { switch self { case .solid: return "Continuo"; case .dashed: return "Tratteggiato"; case .dotted: return "Puntinato" } }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .solid }
    public func lengths(width: Double) -> [Double] {
        switch self { case .solid: return []; case .dashed: return [3 * width, 2 * width]; case .dotted: return [0, 2 * width] }
    }
}
public enum ArrowHeads: String, CaseIterable, Codable, Sendable {
    case none, end, start, both
    public var title: String { switch self { case .none: return "Nessuna"; case .end: return "Fine"; case .start: return "Inizio"; case .both: return "Entrambe" } }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .none }
}
public enum ArrowStyle: String, CaseIterable, Codable, Sendable {
    case open, filled
    public var title: String { self == .open ? "Aperta" : "Piena" }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .open }
}

public struct ShapeStyle: Codable, Equatable, Sendable {
    public var color: InkColor?
    public var width: Double?
    public var fill: InkColor?
    public var fillOpacity: Double?
    public var dash: ShapeDash?
    public var cornerRadius: Double?
    public var arrowHeads: ArrowHeads?
    public var arrowStyle: ArrowStyle?
    public var strokeOpacity: Double?
    public init() { }
    public static var standard: Self { var value = Self(); value.cornerRadius = 8; return value }
    public var isValid: Bool {
        color?.isValid != false && fill?.isValid != false &&
        width.map({ $0.isFinite && $0 > 0 && $0 <= 200 }) != false &&
        cornerRadius.map({ $0.isFinite && (0...10000).contains($0) }) != false &&
        [fillOpacity, strokeOpacity].compactMap { $0 }.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
    public init(_ shape: ShapeElement) {
        color = InkColor(shape.red, shape.green, shape.blue); width = shape.lineWidth
        fill = shape.fill; fillOpacity = shape.fillOpacity; dash = shape.dash
        cornerRadius = shape.cornerRadius; arrowHeads = shape.arrowHeads
        arrowStyle = shape.arrowStyle; strokeOpacity = shape.strokeOpacity
    }
    public func applying(to source: ShapeElement) -> ShapeElement {
        var shape = source
        if let color { shape.red = color.red; shape.green = color.green; shape.blue = color.blue }
        if let width { shape.lineWidth = width }
        shape.fill = fill; shape.fillOpacity = fillOpacity; shape.dash = dash
        shape.cornerRadius = cornerRadius.map { min($0, min(shape.width, shape.height) / 2) }
        shape.arrowHeads = arrowHeads; shape.arrowStyle = arrowStyle; shape.strokeOpacity = strokeOpacity
        return shape
    }
}

public extension ShapeElement {
    var hasValidOptions: Bool {
        guard ShapeStyle(self).isValid,
              cornerRadius.map({ $0 <= min(width, height) / 2 + 0.00001 }) != false,
              innerRatio.map({ $0.isFinite && (0.2...0.8).contains($0) }) != false,
              arcStart?.isFinite != false,
              arcSweep.map({ $0.isFinite && (10 * Double.pi / 180...350 * Double.pi / 180).contains(abs($0)) }) != false,
              sides.map({ (kind == .star ? 4...12 : 3...12).contains($0) }) != false else { return false }
        if let vertices {
            guard (3...64).contains(vertices.count), vertices.allSatisfy(\.isValid) else { return false }
            let unique = Set(vertices.map { "\($0.x)|\($0.y)" })
            guard unique.count == vertices.count else { return false }
        }
        if let anchor = audioAnchor, !anchor.seconds.isFinite || anchor.seconds < 0 || anchor.signature.count > 256 { return false }
        return true
    }
}
