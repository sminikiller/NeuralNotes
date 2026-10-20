import Foundation

public enum PenKind: String, Codable, CaseIterable, Sendable {
    case pen, pencil, monoline, fountainPen, watercolor, crayon
    public var title: String {
        switch self { case .pen: return "Penna"; case .pencil: return "Matita"; case .monoline: return "Monolinea"
        case .fountainPen: return "Stilografica"; case .watercolor: return "Acquerello"; case .crayon: return "Pastello" }
    }
}
public enum EraserKind: String, Codable, CaseIterable, Sendable { case partial, stroke }
public struct PenPreset: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: PenKind
    public var color: InkColor
    public var width: Double
    public init(kind: PenKind, color: InkColor, width: Double) { self.kind = kind; self.color = color; self.width = width }
    public var isValid: Bool { color.isValid && width.isFinite && (0.5...40).contains(width) }
}
public struct WritingOptions: Codable, Equatable, Sendable {
    public var pen = PenKind.pen
    public var eraser = EraserKind.partial
    public var eraserWidth: Double = 18
    public var markerOnly = false
    public var returnToPen = false
    public var presets: [PenPreset] = []
    public init() { }
    public var isValid: Bool { eraserWidth.isFinite && (4...100).contains(eraserWidth) && presets.count <= 5 && presets.allSatisfy(\.isValid) }
}
