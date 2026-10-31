import XCTest

final class SelectiveEraseUITests: XCTestCase {
    @MainActor func testShapeOnlyEraserUsesRealFingerInputAndSupportsOneUndo() async {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let title = app.textFields["notebookNameField"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Gomma selettiva")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Gomma selettiva")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        app.buttons["editorWorkspace"].tap()
        let gestures = app.buttons["Gesti e automatismi"], list = app.collectionViews["workspaceList"]
        for _ in 0..<8 where !(gestures.exists && gestures.isHittable) { list.swipeUp() }
        XCTAssertTrue(gestures.waitForExistence(timeout: 5)); gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Rettangolo"].tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.4)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.6)))
        app.buttons["tool-Gomma"].press(forDuration: 0.6)
        let objects = app.switches["eraserIncludesObjects"]; XCTAssertTrue(objects.waitForExistence(timeout: 5))
        XCTAssertEqual(objects.label, "Cancella anche gli oggetti")
        let target = app.buttons["eraserTarget"]; XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        let shapes = app.buttons["Solo forme e connettori"]; XCTAssertTrue(shapes.waitForExistence(timeout: 5)); shapes.tap()
        app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.8)).tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.65, dy: 0.5)))
        app.buttons["tool-Oggetti"].tap(); app.buttons["Seleziona tutto"].tap()
        XCTAssertFalse(app.buttons["selectionTransfer"].isEnabled)
        app.buttons["editorUndo"].tap(); app.buttons["Seleziona tutto"].tap()
        let handle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shapeHandle-")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selectionTransfer"].isEnabled)
        app.buttons["editorRedo"].tap(); app.buttons["Seleziona tutto"].tap()
        XCTAssertFalse(app.buttons["selectionTransfer"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "shape-only-eraser-undo-redo"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
