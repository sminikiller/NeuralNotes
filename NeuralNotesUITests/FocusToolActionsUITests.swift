import XCTest

final class FocusToolActionsUITests: XCTestCase {
    @MainActor func testFocusToolbarKeepsToolOptionsAndSelectionTransfersAvailableWithoutShrinkingThePage() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-dark"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Solo foglio")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Solo foglio")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap()
        let open = app.buttons["openEditorButton"]; XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let focus = app.buttons["editorFocus"]
        if focus.waitForExistence(timeout: 10), !app.buttons["editorAddText"].exists { focus.tap() }
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["editorAddPage"].tap()
        let counter = app.buttons["editorPageCounter"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina 2 di 2"), object: counter)], timeout: 10)
        app.buttons["editorPreviousPage"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina 1 di 2"), object: counter)], timeout: 10)
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Rettangolo"].tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.5)))
        app.buttons["tool-Oggetti"].tap(); app.buttons["Seleziona tutto"].tap()
        app.buttons["editorFocus"].tap(); app.buttons["editorMiniToolbar"].tap()
        let eraser = app.buttons["focusTool-eraser"]; XCTAssertTrue(eraser.waitForExistence(timeout: 5)); eraser.press(forDuration: 0.6)
        let options = app.descendants(matching: .any)["toolOptions-eraser"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["eraserTarget"].exists)
        XCTAssertGreaterThanOrEqual(options.frame.minX, app.frame.minX); XCTAssertLessThanOrEqual(options.frame.maxX, app.frame.maxX)
        app.coordinate(withNormalizedOffset: .init(dx: 0.08, dy: 0.8)).tap()
        app.buttons["focusToolsSettings"].tap(); app.buttons["Oggetti"].firstMatch.tap()
        let objects = app.buttons["focusTool-objects"]; XCTAssertTrue(objects.waitForExistence(timeout: 5)); objects.tap()
        let frame = canvas.frame
        app.buttons["focusSelectionActions"].tap(); app.buttons["Trascina sulle miniature"].tap()
        XCTAssertTrue(app.buttons["selectionPageDrop-2"].waitForExistence(timeout: 5)); XCTAssertEqual(canvas.frame, frame)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "focus-selection-and-tools"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Chiudi miniature di destinazione"].tap(); XCTAssertFalse(app.buttons["selectionPageDrop-2"].exists)
        XCTAssertTrue(app.buttons["editorMiniToolbar"].exists)
    }
}
