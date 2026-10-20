import Foundation
import XCTest
@testable import NeuralNotesCore

final class EditorWorkspacesTests: XCTestCase {
    func testToolRecentsAreIndependentBoundedAndKeepFavorites() {
        var pen = ToolPalette.standard(for: .pen), marker = ToolPalette.standard(for: .marker)
        let favorites = pen.favorites
        for (i, color) in [InkColor.black, .blue, .red, .green].enumerated() { pen.use(color: color, width: Double(i + 1)) }
        pen.use(color: .blue, width: 2)
        XCTAssertEqual(pen.recentColors, [.blue, .green, .red]); XCTAssertEqual(pen.recentWidths, [2, 4, 3])
        XCTAssertEqual(pen.favorites, favorites); XCTAssertTrue(marker.recentColors.isEmpty)
        marker.use(color: .yellow, width: 6); XCTAssertEqual(marker.recentColors, [.yellow])
        XCTAssertTrue(pen.isValid); XCTAssertTrue(marker.isValid)
    }
    func testActivityProfilesCopyByValueAndRoundTripWithoutOverwritingEachOther() throws {
        var state = NotebookWorkspaces.starter(scratchErase: false)
        let original = state.profiles[0]
        state.profiles[1].dock = .leading; state.profiles[1].favorites = [.line, .ruler, .pen]
        state.selectedID = state.profiles[1].id
        XCTAssertEqual(state.profiles[0], original); XCTAssertFalse(state.selected.scratchErase)
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(try JSONDecoder().decode(NotebookWorkspaces.self, from: JSONEncoder().encode(state)), state)
    }
    func testOldCatalogAndShapeDecodeWithoutNewSettingsOrEndpoints() throws {
        let catalog = try JSONDecoder().decode(DocumentCatalog.self, from: Data(#"{"schemaVersion":1,"attachments":[],"sessions":[]}"#.utf8))
        XCTAssertNil(catalog.editorWorkspaces); XCTAssertNil(catalog.coverDesign)
        let original = ShapeElement(kind: .arrow)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "start"); object.removeValue(forKey: "end")
        let shape = try JSONDecoder().decode(ShapeElement.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(shape.start); XCTAssertNil(shape.end); XCTAssertEqual(shape.kind, .arrow)
    }
    func testInvalidWorkspaceAndNonFinitePaletteCannotPassValidation() {
        var state = NotebookWorkspaces.starter(); state.profiles = []
        XCTAssertFalse(state.isValid)
        state = .starter(); state.selectedID = UUID(); XCTAssertFalse(state.isValid)
        var palette = ToolPalette.standard(for: .pen); palette.recentWidths = [.nan]
        XCTAssertFalse(palette.isValid)
        palette = .standard(for: .pen); palette.use(color: InkColor(.infinity, 0, 0), width: 2)
        XCTAssertTrue(palette.recentColors.isEmpty)
    }
    func testDraggedArrowPreservesBothEndpointsInEveryDirectionAndAfterCoding() throws {
        let start = StrokeSample(x: 200, y: 200)
        for end in [StrokeSample(x: 20, y: 30), StrokeSample(x: 300, y: 30), StrokeSample(x: 20, y: 330), StrokeSample(x: 300, y: 330), StrokeSample(x: 200, y: 40)] {
            let shape = try XCTUnwrap(ShapeElement.dragged(kind: .arrow, from: start, to: end, color: .red, lineWidth: 3))
            let a = try XCTUnwrap(shape.start), b = try XCTUnwrap(shape.end)
            XCTAssertEqual(shape.x + a.x * shape.width, start.x, accuracy: 0.001)
            XCTAssertEqual(shape.y + a.y * shape.height, start.y, accuracy: 0.001)
            XCTAssertEqual(shape.x + b.x * shape.width, end.x, accuracy: 0.001)
            XCTAssertEqual(shape.y + b.y * shape.height, end.y, accuracy: 0.001)
            XCTAssertEqual(try JSONDecoder().decode(ShapeElement.self, from: JSONEncoder().encode(shape)), shape)
        }
        XCTAssertNil(ShapeElement.dragged(kind: .ellipse, from: start, to: start, color: .black, lineWidth: 3))
    }
    func testHeldLineRecognizesSlightWobbleButRejectsScratchAndInvalidInput() {
        let line = (0...30).map { StrokeSample(x: Double($0) * 5, y: 40 + sin(Double($0)) * 1.5) }
        XCTAssertEqual(HeldShapeRecognition.recognize(line), .line)
        let scratch = (0...20).map { StrokeSample(x: $0 % 2 == 0 ? 10 : 80, y: Double($0)) }
        XCTAssertNil(HeldShapeRecognition.recognize(scratch))
        XCTAssertNil(HeldShapeRecognition.recognize([StrokeSample(x: .nan, y: 1)]))
    }
    func testHeldCircleAndRectangleAreDistinctAndOpenCurveIsNotCorrected() {
        let circle = (0...100).map { i -> StrokeSample in
            let a = Double(i) * .pi * 2 / 100
            return StrokeSample(x: 100 + cos(a) * 60, y: 100 + sin(a) * 45)
        }
        XCTAssertEqual(HeldShapeRecognition.recognize(circle), .ellipse)
        var rectangle: [StrokeSample] = []
        let corners = [(20.0, 30.0), (180.0, 30.0), (180.0, 130.0), (20.0, 130.0), (20.0, 30.0)]
        for (a, b) in zip(corners, corners.dropFirst()) {
            for i in 0..<20 { let t = Double(i) / 20; rectangle.append(StrokeSample(x: a.0 + (b.0 - a.0) * t, y: a.1 + (b.1 - a.1) * t)) }
        }
        rectangle.append(StrokeSample(x: 20, y: 30))
        XCTAssertEqual(HeldShapeRecognition.recognize(rectangle), .rectangle)
        XCTAssertNil(HeldShapeRecognition.recognize(Array(circle.prefix(60))))
    }
    func testWorkspaceAndCoverWritesPreserveAudioAndSurvivePackageClone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        _ = try await workspace.addPage()
        let session = AudioSession(title: "Lezione")
        try await workspace.saveSession(session)
        var settings = NotebookWorkspaces.starter(); settings.profiles[1].dock = .trailing
        try await workspace.setEditorWorkspaces(settings)
        var design = CoverDesign(); design.color = .red; design.symbol = "atom"; design.pattern = .grid
        try await workspace.setCoverAppearance(image: nil, design: design)
        let documentID = UUID(), notebookID = UUID()
        try await workspace.clone(to: store, documentID: documentID, notebookID: notebookID)
        let copy = DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
        let catalog = try await copy.catalog()
        XCTAssertEqual(catalog.editorWorkspaces, settings); XCTAssertEqual(catalog.coverDesign, design)
        XCTAssertEqual(catalog.sessions.first?.title, session.title)
        var invalid = settings; invalid.profiles = []
        do { try await copy.setEditorWorkspaces(invalid); XCTFail("Invalid state saved") } catch LibraryFailure.corruptDocument { }
        let unchanged = try await copy.catalog(); XCTAssertEqual(unchanged.editorWorkspaces, settings)
    }
}
