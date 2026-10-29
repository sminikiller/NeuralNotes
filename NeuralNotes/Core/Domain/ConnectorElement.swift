import Foundation

public enum ConnectorRouting: String, Codable, CaseIterable, Sendable {
    case straight, curved, elbow
    public var title: String {
        switch self { case .straight: return "Dritto"; case .curved: return "Curvo"; case .elbow: return "A gomito" }
    }
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .straight
    }
}

public struct ConnectorEnd: Codable, Equatable, Sendable {
    public var objectID: UUID?
    public var anchor: ShapeEndpoint
    public var x: Double, y: Double
    public init(objectID: UUID? = nil, anchor: ShapeEndpoint = .init(x: 0.5, y: 0.5), x: Double, y: Double) {
        self.objectID = objectID; self.anchor = anchor; self.x = x; self.y = y
    }
    public var point: StrokeSample { .init(x: x, y: y) }
    public var isValid: Bool { anchor.isValid && [x, y].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } }
}

public struct ConnectorElement: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var from: ConnectorEnd, to: ConnectorEnd
    public var routing: ConnectorRouting
    public var controlPoints: [StrokeSample]?
    public var style: ShapeStyle?
    public var label: String?
    public var labelRTF: Data?
    public var labelFontSize: Double?
    public var audioAnchor: StrokeAnchor?
    public init(from: ConnectorEnd, to: ConnectorEnd, routing: ConnectorRouting = .curved, style: ShapeStyle? = nil) {
        self.from = from; self.to = to; self.routing = routing; self.style = style
    }
    public var effectiveStyle: ShapeStyle {
        if let style { return style }
        var value = ShapeStyle(); value.color = .blue; value.width = 2; value.arrowHeads = .end; return value
    }
    public var isValid: Bool {
        guard from.isValid, to.isValid, style?.isValid != false,
              (controlPoints?.count ?? 0) <= 16,
              (controlPoints ?? []).allSatisfy({ p in [p.x, p.y].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } }),
              (label?.count ?? 0) <= 100_000, (labelRTF?.count ?? 0) <= 2 * 1024 * 1024,
              labelFontSize.map({ $0.isFinite && (6...200).contains($0) }) != false else { return false }
        if let anchor = audioAnchor, !anchor.seconds.isFinite || anchor.seconds < 0 || anchor.signature.count > 256 { return false }
        return true
    }
}
