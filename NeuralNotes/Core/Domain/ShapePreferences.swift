import Foundation

public enum ShapeRecognitionMode: String, CaseIterable, Codable, Sendable {
    case off, hold, automatic
    public var title: String { switch self { case .off: return "Spento"; case .hold: return "Tieni ferma la punta"; case .automatic: return "Automatico al rilascio" } }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .off }
}
public enum ShapeRecognitionOutput: String, CaseIterable, Codable, Sendable {
    case editable, ink
    public var title: String { self == .editable ? "Forma modificabile" : "Tratto di penna" }
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .ink }
}
public struct ShapePreferences: Codable, Equatable, Sendable {
    public var mode: ShapeRecognitionMode?
    public var output: ShapeRecognitionOutput?
    public var enabledKinds: [ShapeKind]?
    public var style: ShapeStyle?
    public var sides: Int?
    public var innerRatio: Double?
    public init() { }
    public var isValid: Bool {
        style?.isValid != false && sides.map({ (3...12).contains($0) }) != false &&
        innerRatio.map({ $0.isFinite && (0.2...0.8).contains($0) }) != false &&
        enabledKinds.map { $0.count <= 64 } != false
    }
    public var kinds: [ShapeKind] {
        var seen = Set<ShapeKind>()
        return (enabledKinds ?? ShapeKind.allCases).filter { seen.insert($0).inserted }
    }
}
