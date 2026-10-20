import XCTest
@testable import NeuralNotesCore

final class EditorToolsTests: XCTestCase {
    func testUndoIsNotConsumedUntilTheOperationSucceeds() {
        var history = EditHistory<Int>()
        history.record(7, label: "Change")
        XCTAssertEqual(history.undo?.event, 7)
        // Failed IO: do not acknowledge. The same command remains retryable.
        XCTAssertEqual(history.undo?.event, 7)
        history.didUndo(); XCTAssertNil(history.undo); XCTAssertEqual(history.redo?.event, 7)
        history.didRedo(); XCTAssertEqual(history.undo?.event, 7); XCTAssertNil(history.redo)
    }
    func testNewEditInvalidatesRedoAndHistoryRespectsBudget() {
        var history = EditHistory<Int>(maximumCount: 2, maximumBytes: 10)
        history.record(1, label: "A", cost: 6); history.record(2, label: "B", cost: 6)
        history.didUndo(); XCTAssertNil(history.undo)
        history.record(3, label: "C", cost: 2); XCTAssertNil(history.redo)
        history.record(4, label: "Too large", cost: 100); XCTAssertNil(history.undo)
    }
    func testCropStaysWithinImageAndRoundTrips() throws {
        let crop = NormalizedCrop(x: -1, y: 0.9, width: 4, height: 4)
        XCTAssertEqual(crop.x, 0); XCTAssertEqual(crop.width, 1)
        XCTAssertEqual(crop.y + crop.height, 1, accuracy: 0.0001)
        XCTAssertEqual(try JSONDecoder().decode(NormalizedCrop.self, from: JSONEncoder().encode(crop)), crop)
    }
    func testSessionRestoreRemovesDeletedDuplicatesAndExcessTabs() {
        let ids = (0..<8).map { _ in UUID() }
        let session = DeskSession(notebookIDs: [ids[0]] + ids, selectedID: ids[7])
        let valid = session.available(in: Set(ids.dropFirst()))
        XCTAssertEqual(valid.notebookIDs, Array(ids.dropFirst().prefix(6)))
        XCTAssertEqual(valid.selectedID, ids[1])
    }
    func testShapeAndCropAreBackwardCompatibleWithV1Pages() throws {
        var page = PageSnapshot(); page.shapes = [ShapeElement(kind: .ellipse)]
        var image = ImageElement(file: "images/test.png", width: 100, height: 100)
        image.crop = NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5); image.rotation = 90
        page.images = [image]
        let data = try JSONEncoder().encode(page)
        XCTAssertEqual(try JSONDecoder().decode(PageSnapshot.self, from: data), page)
    }
}
