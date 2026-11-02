import XCTest
@testable import NeuralNotesCore

final class NamedPaletteAndSectionMovesTests: XCTestCase {
    func testNamedPaletteDoesNotChangeToolRecentsAndSurvivesWorkspaceCoding() throws {
        var workspace = EditorWorkspace(name: "Biologia", favorites: [.pen, .marker])
        var recent = workspace.palette(for: .pen); recent.use(color: .red, width: 3); workspace.palettes["pen"] = recent
        let palette = NamedInkPalette(name: "Biologia", colors: [.green, .blue, .black])
        XCTAssertTrue(workspace.saveNamedPalette(palette)); workspace.activeNamedPaletteID = palette.id
        XCTAssertEqual(workspace.displayedColors(for: .pen), [.green, .blue, .black, .red])
        XCTAssertEqual(workspace.palette(for: .pen).recentColors, [.red])
        XCTAssertTrue(workspace.palette(for: .marker).recentColors.isEmpty)
        XCTAssertTrue(workspace.isValid)
        XCTAssertEqual(try JSONDecoder().decode(EditorWorkspace.self, from: JSONEncoder().encode(workspace)), workspace)
        workspace.removeNamedPalette(palette.id); XCTAssertNil(workspace.activeNamedPaletteID)
        XCTAssertEqual(workspace.displayedColors(for: .pen), [.red, .black, .blue])
    }
    func testPalettesRejectDuplicatesInvalidChannelsAndDanglingSelection() {
        var workspace = EditorWorkspace(name: "A", favorites: [.pen])
        XCTAssertFalse(workspace.saveNamedPalette(.init(name: "", colors: [.red])))
        XCTAssertFalse(workspace.saveNamedPalette(.init(name: "A", colors: [.red, .red])))
        XCTAssertFalse(workspace.saveNamedPalette(.init(name: "A", colors: [.init(.nan, 0, 0)])))
        workspace.activeNamedPaletteID = UUID(); XCTAssertFalse(workspace.isValid)
        workspace.activeNamedPaletteID = nil
        for i in 0..<NamedInkPalette.maximumSets { XCTAssertTrue(workspace.saveNamedPalette(.init(name: "Materia \(i)", colors: [.blue]))) }
        XCTAssertFalse(workspace.saveNamedPalette(.init(name: "Troppa", colors: [.black])))
    }
    func testSectionMovesPreserveSubtreesAndPagesWithIndentOutdentAndCollapse() throws {
        let a = NotebookSection(title: "A", pageIDs: [UUID()]), b = NotebookSection(title: "B"), c = NotebookSection(title: "C")
        let child = NotebookSection(title: "Figlio", parentID: b.id, pageIDs: [UUID()])
        let original = [a, b, child, c]
        let indented = try NotebookSections.indenting(b.id, in: original)
        XCTAssertEqual(indented.first { $0.id == b.id }?.parentID, a.id)
        XCTAssertEqual(NotebookSections.outline(indented).map(\.depth), [0, 1, 2, 0])
        XCTAssertEqual(NotebookSections.visibleOutline(indented, collapsed: [a.id]).map(\.section.id), [a.id, c.id])
        let restored = try NotebookSections.outdenting(b.id, in: indented)
        XCTAssertEqual(restored, original)
        let moved = try NotebookSections.moving(b.id, to: nil, before: a.id, in: original)
        XCTAssertEqual(moved.map(\.id), [b.id, child.id, a.id, c.id])
        XCTAssertEqual(Set(moved.flatMap(\.pageIDs)), Set(original.flatMap(\.pageIDs)))
        XCTAssertThrowsError(try NotebookSections.moving(b.id, to: child.id, in: original))
        XCTAssertThrowsError(try NotebookSections.moving(b.id, to: nil, before: child.id, in: original))
    }
    func testSectionMoveCannotExceedDepthOrInventParents() throws {
        var chain: [NotebookSection] = []
        for i in 0..<12 { chain.append(NotebookSection(title: "S\(i)", parentID: chain.last?.id)) }
        let extra = NotebookSection(title: "Extra")
        XCTAssertThrowsError(try NotebookSections.moving(extra.id, to: chain.last!.id, in: chain + [extra]))
        XCTAssertThrowsError(try NotebookSections.moving(extra.id, to: UUID(), in: chain + [extra]))
    }
}
