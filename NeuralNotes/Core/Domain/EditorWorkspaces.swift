import Foundation

public struct InkColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double, green: Double, blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) {
        func channel(_ value: Double) -> Double { value.isFinite && (0...1).contains(value) ? (value * 255).rounded() / 255 : value }
        self.red = channel(red); self.green = channel(green); self.blue = channel(blue)
    }
    public var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    public static let black = InkColor(0, 0, 0), blue = InkColor(0.1, 0.35, 0.95), red = InkColor(0.95, 0.15, 0.2)
    public static let yellow = InkColor(1, 0.83, 0.12), green = InkColor(0.2, 0.8, 0.4), orange = InkColor(1, 0.5, 0.1)
    public var hex: String { isValid ? String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) : "#000000" }
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }), let number = UInt32(value, radix: 16) else { return nil }
        self.init(Double((number >> 16) & 255) / 255, Double((number >> 8) & 255) / 255, Double(number & 255) / 255)
    }
}

public enum WorkspaceTool: String, Codable, CaseIterable, Sendable {
    case pen, marker, eraser, lasso, objects, text, audioLink, line, arrow, ellipse, rectangle, triangle, ruler, protractor, lens
    public init(from decoder: Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .pen }
}

public struct ToolPalette: Codable, Equatable, Sendable {
    public var favorites: [InkColor]
    public var recentColors: [InkColor] = []
    public var recentWidths: [Double] = []
    public init(favorites: [InkColor]) { self.favorites = favorites }
    public static func standard(for tool: WorkspaceTool) -> Self {
        ToolPalette(favorites: tool == .marker ? [.yellow, .green, .orange] : [.black, .blue, .red])
    }
    public mutating func use(color: InkColor, width: Double) {
        guard color.isValid, width.isFinite, (0.5...40).contains(width) else { return }
        recentColors.removeAll { $0 == color }; recentColors.insert(color, at: 0); recentColors = Array(recentColors.prefix(3))
        recentWidths.removeAll { abs($0 - width) < 0.01 }; recentWidths.insert(width, at: 0); recentWidths = Array(recentWidths.prefix(3))
    }
    public var isValid: Bool {
        favorites.count <= 6 && recentColors.count <= 3 && recentWidths.count <= 3 &&
        (favorites + recentColors).allSatisfy(\.isValid) && recentWidths.allSatisfy { $0.isFinite && (0.5...40).contains($0) }
    }
}

public enum ToolbarDock: String, Codable, CaseIterable, Sendable {
    case top, bottom, leading, trailing
    public var title: String {
        switch self { case .top: return "In alto"; case .bottom: return "In basso"; case .leading: return "A sinistra"; case .trailing: return "A destra" }
    }
    public var vertical: Bool { self == .leading || self == .trailing }
}

public struct EditorWorkspace: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var favorites: [WorkspaceTool]
    public var dock = ToolbarDock.top
    public var showPages = true, showStatus = true, holdShapes = true, scratchErase = true, pullNext = true
    public var palettes: [String: ToolPalette] = [:]
    public var writing: WritingOptions?
    public var focusTools: [WorkspaceTool]?
    public var shapes: ShapePreferences?
    public var snapping: SnapPreferences?
    public var protractorKind: ProtractorGuide.Kind?
    public static let maximumFocusTools = 5
    public var effectiveFocusTools: [WorkspaceTool] { focusTools ?? Array(favorites.prefix(3)) }
    public init(name: String, favorites: [WorkspaceTool]) { self.name = name; self.favorites = favorites }
    private enum CodingKeys: String, CodingKey {
        case id, name, favorites, dock, showPages, showStatus, holdShapes, scratchErase, pullNext, palettes, writing, focusTools, shapes, snapping, protractorKind
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        func tools(_ key: CodingKeys, maximum: Int) throws -> [WorkspaceTool]? {
            guard let names = try values.decodeIfPresent([String].self, forKey: key) else { return nil }
            guard names.count <= 256 else { throw LibraryFailure.corruptDocument }
            var seen = Set<WorkspaceTool>()
            return Array(names.compactMap(WorkspaceTool.init(rawValue:)).filter { seen.insert($0).inserted }.prefix(maximum))
        }
        let known = try tools(.favorites, maximum: 8) ?? []
        favorites = known.isEmpty ? [.pen] : known
        let focus = try tools(.focusTools, maximum: Self.maximumFocusTools)
        focusTools = focus?.isEmpty == true ? nil : focus
        dock = try values.decodeIfPresent(ToolbarDock.self, forKey: .dock) ?? .top
        showPages = try values.decodeIfPresent(Bool.self, forKey: .showPages) ?? true
        showStatus = try values.decodeIfPresent(Bool.self, forKey: .showStatus) ?? true
        holdShapes = try values.decodeIfPresent(Bool.self, forKey: .holdShapes) ?? true
        scratchErase = try values.decodeIfPresent(Bool.self, forKey: .scratchErase) ?? true
        pullNext = try values.decodeIfPresent(Bool.self, forKey: .pullNext) ?? true
        palettes = try values.decodeIfPresent([String: ToolPalette].self, forKey: .palettes) ?? [:]
        palettes = palettes.filter { WorkspaceTool(rawValue: $0.key) != nil }
        writing = try values.decodeIfPresent(WritingOptions.self, forKey: .writing)
        shapes = try values.decodeIfPresent(ShapePreferences.self, forKey: .shapes)
        snapping = try values.decodeIfPresent(SnapPreferences.self, forKey: .snapping)
        protractorKind = try values.decodeIfPresent(ProtractorGuide.Kind.self, forKey: .protractorKind)
    }
    public func palette(for tool: WorkspaceTool) -> ToolPalette { palettes[tool.rawValue] ?? .standard(for: tool) }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40 &&
        (1...8).contains(favorites.count) && Set(favorites).count == favorites.count && palettes.count <= WorkspaceTool.allCases.count &&
        palettes.allSatisfy { WorkspaceTool(rawValue: $0.key) != nil && $0.value.isValid } && (writing?.isValid ?? true) && shapes?.isValid != false &&
        (focusTools.map { (1...Self.maximumFocusTools).contains($0.count) && Set($0).count == $0.count } ?? true)
    }
}

public struct NotebookWorkspaces: Codable, Equatable, Sendable {
    public var profiles: [EditorWorkspace]
    public var selectedID: UUID
    public init(profiles: [EditorWorkspace], selectedID: UUID) { self.profiles = profiles; self.selectedID = selectedID }
    public var selected: EditorWorkspace { profiles.first { $0.id == selectedID } ?? profiles[0] }
    public static func starter(scratchErase: Bool = true, pullNext: Bool = true) -> Self {
        var profiles = [EditorWorkspace(name: "Scrittura", favorites: [.pen, .marker, .eraser, .lasso, .text, .objects]),
            EditorWorkspace(name: "Matematica", favorites: [.pen, .ruler, .protractor, .line, .arrow, .ellipse, .rectangle]),
            EditorWorkspace(name: "Lettura", favorites: [.marker, .pen, .text, .lasso]),
            EditorWorkspace(name: "Disegno", favorites: [.pen, .eraser, .ellipse, .rectangle, .objects])]
        for i in profiles.indices { profiles[i].scratchErase = scratchErase; profiles[i].pullNext = pullNext }
        return Self(profiles: profiles, selectedID: profiles[0].id)
    }
    public var isValid: Bool {
        (1...12).contains(profiles.count) && Set(profiles.map(\.id)).count == profiles.count &&
        profiles.contains { $0.id == selectedID } && profiles.allSatisfy(\.isValid)
    }
}

public enum CoverPattern: String, Codable, CaseIterable, Sendable {
    case plain, diagonal, grid, dots
    public var title: String {
        switch self { case .plain: return "Essenziale"; case .diagonal: return "Geometrica"; case .grid: return "Griglia"; case .dots: return "Puntini" }
    }
}
public struct CoverDesign: Codable, Equatable, Sendable {
    public var color: InkColor?
    public var pattern = CoverPattern.diagonal
    public var symbol = "sparkles"
    public init() { }
    public static let symbols = ["sparkles", "function", "atom", "leaf", "book", "pencil.tip", "globe", "music.note", "lightbulb"]
    public var isValid: Bool { (color?.isValid ?? true) && Self.symbols.contains(symbol) }
    public static func suggested(id: UUID, title: String) -> Self {
        var value = Self()
        let index = Int(id.uuid.0) % CoverPattern.allCases.count
        value.pattern = CoverPattern.allCases[index]
        value.symbol = ["matem", "math", "fisic"].contains(where: { title.lowercased().contains($0) }) ? "function" : Self.symbols[Int(id.uuid.1) % Self.symbols.count]
        return value
    }
}
