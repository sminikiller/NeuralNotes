import Foundation

/// A subject's palette belongs to its notebook workspace, independently of
/// each tool's favorite colors, recent colors and recent widths.
public struct NamedInkPalette: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colors: [InkColor]
    public static let maximumSets = 20, maximumColors = 12
    public init(id: UUID = UUID(), name: String, colors: [InkColor]) {
        self.id = id; self.name = name; self.colors = colors
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40 &&
        (1...Self.maximumColors).contains(colors.count) && colors.allSatisfy(\.isValid) && Set(colors).count == colors.count
    }
}

public extension EditorWorkspace {
    var activeNamedPalette: NamedInkPalette? { namedPalettes?.first { $0.id == activeNamedPaletteID } }
    /// Subject colors first, then independent recent/favorite tool colors.
    func displayedColors(for tool: WorkspaceTool) -> [InkColor] {
        let personal = palette(for: tool)
        var seen = Set<InkColor>()
        return ((activeNamedPalette?.colors ?? []) + personal.recentColors + personal.favorites).filter { seen.insert($0).inserted }
    }
    @discardableResult
    mutating func saveNamedPalette(_ palette: NamedInkPalette) -> Bool {
        guard palette.isValid else { return false }
        var all = namedPalettes ?? []
        if let i = all.firstIndex(where: { $0.id == palette.id }) { all[i] = palette }
        else { guard all.count < NamedInkPalette.maximumSets else { return false }; all.append(palette) }
        namedPalettes = all; return true
    }
    mutating func removeNamedPalette(_ id: UUID) {
        namedPalettes?.removeAll { $0.id == id }
        if activeNamedPaletteID == id { activeNamedPaletteID = nil }
    }
}
