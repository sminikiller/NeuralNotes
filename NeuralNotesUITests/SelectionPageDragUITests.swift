import XCTest

final class SelectionPageDragUITests: XCTestCase {
    @MainActor func testHeldSelectionReallyDragsToThumbnailWithoutResizingTheCanvasAndUndoesOnce() {
        continueAfterFailure = false
        let device = XCUIDevice.shared, original = device.orientation
        device.orientation = .portrait; defer { device.orientation = original }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Trascinamento"); app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Trascinamento")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        let editor = app.buttons["openEditorButton"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let focus = app.buttons["editorFocus"]
        if focus.waitForExistence(timeout: 10), !app.buttons["editorAddText"].exists { focus.tap() }
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        tapReady(app.buttons["editorAddPage"]); page(2, in: app)
        tapReady(app.buttons["editorPreviousPage"]); page(1, in: app)
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Rettangolo"].tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.5)))
        app.buttons["tool-Oggetti"].tap(); app.buttons["Seleziona tutto"].tap()
        let frame = canvas.frame
        let rail = app.buttons["selectionPageDrag"]; XCTAssertTrue(rail.waitForExistence(timeout: 5)); rail.tap()
        let destination = app.buttons["selectionPageDrop-2"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); XCTAssertTrue(destination.isHittable)
        XCTAssertEqual(canvas.frame, frame, "La striscia deve sovrapporsi senza ridurre lo spazio del foglio")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "selection-drag-rail"; attachment.lifetime = .keepAlways; add(attachment)
        let source = app.descendants(matching: .any)["selectionDragSource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5)); XCTAssertTrue(source.isHittable)
        source.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.8,
            thenDragTo: destination.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.3)
        page(2, in: app)
        app.buttons["Seleziona tutto"].tap()
        let handle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shapeHandle-")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        tapReady(app.buttons["editorUndo"]); page(1, in: app)
        app.buttons["Seleziona tutto"].tap(); XCTAssertTrue(handle.waitForExistence(timeout: 5))
        tapReady(app.buttons["editorRedo"]); page(2, in: app)
        app.buttons["Seleziona tutto"].tap(); XCTAssertTrue(handle.waitForExistence(timeout: 5))
        tapReady(app.buttons["editorPreviousPage"]); page(1, in: app)
        app.buttons["Seleziona tutto"].tap(); XCTAssertFalse(app.buttons["selectionTransfer"].isEnabled)
    }
    @MainActor private func page(_ number: Int, in app: XCUIApplication) {
        let counter = app.buttons["editorPageCounter"]; XCTAssertTrue(counter.waitForExistence(timeout: 15))
        // Xcode26.6 can take more than12s to obtain an AX snapshot while the
        // page is already visibly correct. Keep the exact state assertion.
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina \(number) di 2"), object: counter)], timeout: 30)
    }
    @MainActor private func tapReady(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND isHittable == true"), object: button)], timeout: 30)
        button.tap()
    }
}
