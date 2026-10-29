import XCTest
@testable import NeuralNotesCore

final class SnapEngineTests: XCTestCase {
    private let page = SnapRect(x: 0, y: 0, width: 10000, height: 10000)
    private func object(_ x: Double, _ y: Double, _ width: Double = 80, _ height: Double = 80, rotation: Double = 0, locked: Bool = false) -> SnapObject {
        .init(id: UUID(), rect: .init(x: x, y: y, width: width, height: height), rotation: rotation, locked: locked)
    }
    func testEdgesCentresAndPageMarginUseScreenTolerance() {
        let engine = SnapEngine(objects: [object(100, 100)], page: page, margin: 64)
        XCTAssertEqual(engine.snap(.init(x: 97, y: 300, width: 20, height: 20), zoom: 1).rect.x, 100)
        XCTAssertEqual(engine.snap(.init(x: 131, y: 300, width: 20, height: 20), zoom: 1).rect.x, 130)
        XCTAssertEqual(engine.snap(.init(x: 97, y: 300, width: 20, height: 20), zoom: 4).rect.x, 97)
        XCTAssertEqual(engine.snap(.init(x: 60, y: 300, width: 20, height: 20), zoom: 1).rect.x, 64)
        XCTAssertEqual(engine.snap(.init(x: 4989, y: 300, width: 20, height: 20), zoom: 1).rect.x, 4990)
        XCTAssertEqual(engine.snap(.init(x: 9979, y: 300, width: 20, height: 20), zoom: 1).rect.maxX, 10000)
    }
    func testLockedRotatedAndMovingObjectsAreNotReferences() {
        let locked = object(100, 100, locked: true), rotated = object(200, 200, rotation: 30), selected = object(300, 300)
        let engine = SnapEngine(objects: [locked, rotated, selected], excluding: [selected.id], page: page)
        for x in [97.0, 197, 297] {
            XCTAssertEqual(engine.snap(.init(x: x, y: 600, width: 10, height: 10), zoom: 1).rect.x, x)
        }
    }
    func testEqualSpacingBetweenTwoObjectsShowsBothMeasurements() {
        let engine = SnapEngine(objects: [object(100, 100, 20, 40), object(260, 100, 20, 40)], page: page)
        let result = engine.snap(.init(x: 181, y: 100, width: 20, height: 40), zoom: 1)
        XCTAssertEqual(result.rect.x, 180)
        XCTAssertEqual(result.guides.compactMap(\.distance), [60, 60])
        let vertical = SnapEngine(objects: [object(100, 100, 40, 20), object(100, 260, 40, 20)], page: page)
        XCTAssertEqual(vertical.snap(.init(x: 100, y: 181, width: 40, height: 20), zoom: 1).rect.y, 180)
    }
    func testResizeAndPointSnapWorkInBothDirections() {
        let engine = SnapEngine(objects: [object(300, 400)], page: page)
        let result = engine.snap(.init(x: 200, y: 300, width: 97, height: 97), zoom: 1, resizing: true)
        XCTAssertEqual(result.rect, .init(x: 200, y: 300, width: 100, height: 100))
        for point in [StrokeSample(x: 297, y: 397), .init(x: 303, y: 403)] {
            XCTAssertEqual(engine.snapPoint(point, zoom: 1).point, .init(x: 300, y: 400))
        }
    }
    func testGridOriginsMillimetresAndAutomaticDefaults() throws {
        var preferences = SnapPreferences(); preferences.objects = false
        let grid = try XCTUnwrap(SnapGrid.forPaper(.grid, appearance: .init(spacing: 24), enabled: nil))
        let result = SnapEngine(objects: [], page: page, grid: grid).snap(.init(x: 27, y: 53, width: 20, height: 20), zoom: 1, preferences: preferences)
        XCTAssertEqual(result.rect.x, 24); XCTAssertEqual(result.rect.y, 48)
        XCTAssertNil(SnapGrid.forPaper(.plain, appearance: nil, enabled: nil))
        XCTAssertNil(SnapGrid.forPaper(.grid, appearance: nil, enabled: false))
        XCTAssertEqual(SnapGrid.forPaper(.plain, appearance: nil, enabled: true)?.step, 8)
        XCTAssertEqual(SnapGrid.forPaper(.millimeter, appearance: .init(spacing: 32), enabled: nil)?.step, 8)
    }
    func testIsometricGridHasObliqueOffsetAndUsesDistanceThreshold() throws {
        let grid = SnapGrid(step: 24, isometric: true)
        let point = try XCTUnwrap(grid.nearest(.init(x: 25, y: 14)))
        XCTAssertEqual(point.x, 24 * sqrt(3) / 2, accuracy: 0.001); XCTAssertEqual(point.y, 12, accuracy: 0.001)
        for sample in [StrokeSample(x: 27, y: 81), .init(x: 100, y: 300), .init(x: -18, y: 54)] {
            let nearest = try XCTUnwrap(grid.nearest(sample))
            let a = (nearest.y - nearest.x / sqrt(3)) / 24, b = (nearest.y + nearest.x / sqrt(3)) / 24
            XCTAssertEqual(a, a.rounded(), accuracy: 0.0001); XCTAssertEqual(b, b.rounded(), accuracy: 0.0001)
        }
        var preferences = SnapPreferences(); preferences.objects = false
        let engine = SnapEngine(objects: [], page: page, grid: grid)
        XCTAssertTrue(engine.snapPoint(.init(x: point.x + 1, y: point.y + 1), zoom: 1, preferences: preferences).snapped)
        XCTAssertFalse(engine.snapPoint(.init(x: point.x + 5, y: point.y + 5), zoom: 1, preferences: preferences).snapped)
    }
    func testDisabledOptionsAndSuspensionHaveNoResidualEffect() {
        let source = SnapRect(x: 97, y: 97, width: 20, height: 20)
        let engine = SnapEngine(objects: [object(100, 100)], page: page)
        var preferences = SnapPreferences(); preferences.objects = false; preferences.grid = false
        let disabled = engine.snap(source, zoom: 1, preferences: preferences)
        XCTAssertEqual(disabled.rect, source); XCTAssertTrue(disabled.guides.isEmpty)
        let gridEngine = SnapEngine(objects: [], page: page, grid: .init(step: 100))
        XCTAssertEqual(gridEngine.snap(source, zoom: 1, preferences: preferences).rect, source)
        let suspended = engine.snap(source, zoom: 1, suspended: true)
        XCTAssertEqual(suspended.rect, source); XCTAssertTrue(suspended.guides.isEmpty)
        preferences.objects = true; preferences.guides = false
        let hidden = engine.snap(source, zoom: 1, preferences: preferences)
        XCTAssertNotEqual(hidden.rect, source); XCTAssertTrue(hidden.guides.isEmpty)
        XCTAssertEqual(SnapEngine.rotation(88), 90); XCTAssertEqual(SnapEngine.rotation(91.9), 90)
        XCTAssertEqual(SnapEngine.rotation(44), 45); XCTAssertEqual(SnapEngine.rotation(41), 41)
        XCTAssertEqual(SnapEngine.rotation(88, suspended: true), 88)
    }
    func testMalformedGeometryIsIgnoredAndWorkspaceFieldIsOptional() throws {
        let bad = object(.nan, 10), engine = SnapEngine(objects: [bad], page: page)
        let source = SnapRect(x: 97, y: 97, width: 20, height: 20)
        XCTAssertEqual(engine.snap(source, zoom: .nan).rect, source)
        XCTAssertNil(SnapGrid(step: .infinity).nearest(.init(x: 1, y: 1)))
        var old = EditorWorkspace(name: "Prima", favorites: [.pen]); XCTAssertNil(old.snapping)
        var prefs = SnapPreferences(); prefs.objects = false; prefs.grid = true; prefs.guides = false
        old.snapping = prefs
        XCTAssertEqual(try JSONDecoder().decode(EditorWorkspace.self, from: JSONEncoder().encode(old)).snapping, prefs)
    }
    func testAspectRatioLockSquareSnapAndFreeResize() {
        let shape = ShapeElement(kind: .rectangle, x: 100, y: 100, width: 100, height: 50)
        let target = StrokeSample(x: 204, y: 200)
        let square = ShapeHandles.moved(shape, handle: .corner(2), to: target)
        XCTAssertEqual(square.width, square.height)
        let free = ShapeHandles.moved(shape, handle: .corner(2), to: target, snapProportions: false)
        XCTAssertEqual(free.width, 104); XCTAssertEqual(free.height, 100)
        let locked = ShapeHandles.moved(shape, handle: .corner(2), to: target, keepProportions: true)
        XCTAssertEqual(locked.width / locked.height, 2)
    }
    func testCachedLargePageQueriesStayWithinAFrameBudgetOnTheRunner() {
        let values = (0..<5000).map { object(Double($0 % 100) * 90 + 30, Double($0 / 100) * 100 + 30, 30, 40) }
        let engine = SnapEngine(objects: values, page: page)
        let start = Date()
        for i in 0..<2000 {
            let result = engine.snap(.init(x: Double(i % 100) * 90 + 32, y: 873, width: 30, height: 40), zoom: 1)
            XCTAssertTrue(result.rect.valid)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 2000, 0.016)
    }
}
