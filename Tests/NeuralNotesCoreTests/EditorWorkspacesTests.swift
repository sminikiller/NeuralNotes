import Foundation
import XCTest
@testable import NeuralNotesCore

final class EditorWorkspacesTests: XCTestCase {
    func testFutureToolsAreFilteredWithoutDuplicatingFallbackPensOrLosingPreferences() throws {
        let source = EditorWorkspace(name: "Fisica", favorites: [.marker, .protractor, .pen])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        json["favorites"] = ["futureInk", "marker", "protractor", "marker", "futureTool", "pen"]
        json["focusTools"] = ["futureInk", "protractor", "pen", "pen"]
        json["protractorKind"] = "futureGeometry"
        let read = try JSONDecoder().decode(EditorWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(read.favorites, [.marker, .protractor, .pen]); XCTAssertEqual(read.focusTools, [.protractor, .pen])
        XCTAssertEqual(read.protractorKind, .semicircle); XCTAssertTrue(read.isValid)
        XCTAssertEqual(try JSONDecoder().decode(EditorWorkspace.self, from: JSONEncoder().encode(read)), read)
    }
    func testLegacyMinimalWorkspaceDefaultsAndUnknownPaletteDoNotPreventOpening() throws {
        var json: [String: Any] = ["id": UUID().uuidString, "name": "Personale", "favorites": ["unavailable"]]
        let palette = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ToolPalette.standard(for: .pen)))
        json["palettes"] = ["pen": palette, "futureInk": palette]
        let read = try JSONDecoder().decode(EditorWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(read.favorites, [.pen]); XCTAssertNil(read.focusTools); XCTAssertNil(read.protractorKind)
        XCTAssertEqual(read.palettes.count, 1); XCTAssertTrue(read.showPages); XCTAssertTrue(read.isValid)
    }
    func testHeldTriangleAndArrowPreserveGeometryAndRejectOpenTriangle() {
        func samples(_ vertices: [StrokeSample]) -> [StrokeSample] {
            var result: [StrokeSample] = []
            for (a, b) in zip(vertices, vertices.dropFirst()) {
                for i in 0..<30 {
                    let t = Double(i) / 30
                    result.append(StrokeSample(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            if let last = vertices.last { result.append(last) }; return result
        }
        let triangle = samples([StrokeSample(x: 45, y: 20), StrokeSample(x: 140, y: 80), StrokeSample(x: 10, y: 120), StrokeSample(x: 45, y: 20)])
        XCTAssertEqual(HeldShapeRecognition.recognize(triangle), .triangle)
        XCTAssertEqual(HeldShapeRecognition.triangleVertices(triangle)?.count, 3)
        XCTAssertNil(HeldShapeRecognition.triangleVertices(Array(triangle.prefix(45))))
        let arrow = samples([StrokeSample(x: 10, y: 20), StrokeSample(x: 150, y: 20), StrokeSample(x: 125, y: 5), StrokeSample(x: 150, y: 20), StrokeSample(x: 125, y: 35)])
        XCTAssertEqual(HeldShapeRecognition.recognize(arrow), .arrow)
        XCTAssertEqual(HeldShapeRecognition.arrowEndpoints(arrow)?.1.x, 150)
        XCTAssertNil(HeldShapeRecognition.arrowEndpoints(Array(arrow.prefix(65))))
    }
    func testHeldLineRecognitionHandlesDiagonalAndVerticalDirections() {
        for direction in [-1.0, 1.0] {
            let diagonal = (0...30).map { i -> StrokeSample in
                let t = Double(i)
                return StrokeSample(x: 200 + direction * t * 4, y: 300 + t * 3 + sin(t) * 0.5)
            }
            XCTAssertEqual(HeldShapeRecognition.recognize(diagonal), .line)
        }
        let vertical = (0...30).map { StrokeSample(x: 140, y: Double($0) * 4) }
        XCTAssertEqual(HeldShapeRecognition.recognize(vertical), .line)
    }
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
        XCTAssertNil(catalog.coverUsesLastEditedPage)
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
        var page = try await workspace.addPage(); page.revision = 1
        page = try await workspace.save(page, drawing: Data([42]))
        let session = AudioSession(title: "Lezione")
        try await workspace.saveSession(session)
        var settings = NotebookWorkspaces.starter(); settings.profiles[1].dock = .trailing
        try await workspace.setEditorWorkspaces(settings)
        var design = CoverDesign(); design.color = .red; design.symbol = "atom"; design.pattern = .grid
        try await workspace.setCoverAppearance(image: nil, design: design, useLastEditedPage: true)
        try await workspace.setEditorWorkspaces(settings)
        let documentID = UUID(), notebookID = UUID()
        try await workspace.clone(to: store, documentID: documentID, notebookID: notebookID)
        let copy = DocumentWorkspace(package: store.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
        let catalog = try await copy.catalog()
        XCTAssertEqual(catalog.editorWorkspaces, settings); XCTAssertEqual(catalog.coverDesign, design)
        XCTAssertEqual(catalog.coverUsesLastEditedPage, true)
        let lastEdited = try await copy.lastEditedPage()
        XCTAssertNotEqual(lastEdited?.id, page.id)
        XCTAssertEqual(lastEdited?.lastEditedAt, page.lastEditedAt)
        XCTAssertEqual(catalog.sessions.first?.title, session.title)
        var invalid = settings; invalid.profiles = []
        do { try await copy.setEditorWorkspaces(invalid); XCTFail("Invalid state saved") } catch LibraryFailure.corruptDocument { }
        let unchanged = try await copy.catalog(); XCTAssertEqual(unchanged.editorWorkspaces, settings)
    }
}
