import XCTest

final class EditorQuickActionsUITests: XCTestCase {
    @MainActor func testLongPressShowsOptionsAnchoredToPenAndEraser() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["tool-Penna"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Tipo di penna"].waitForExistence(timeout: 5) || app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tipo di penna")).firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).tap()
        app.buttons["tool-Gomma"].press(forDuration: 0.6)
        XCTAssertTrue(app.switches["Solo evidenziatore"].waitForExistence(timeout: 5))
    }
    @MainActor func testPhotoLibraryOpensAndCancelReturnsToTheSameCanvas() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Inserisci foto"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Annulla"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8)); cancel.tap()
        XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["pencilCanvas"].firstMatch.exists)
    }
    @MainActor
    func testChangingPageModeKeepsTheFullEditorCanvasBounds() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorPageNavigation"].tap(); app.buttons["Pagina singola"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let original = canvas.frame
        for title in ["Scorrimento verticale", "Sfoglia orizzontalmente", "Pagina singola"] {
            app.buttons["editorPageNavigation"].tap(); app.buttons[title].tap()
            let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(canvas.frame.width - original.width) <= 2 && abs(canvas.frame.height - original.height) <= 2
            }, object: canvas)
            wait(for: [stable], timeout: 5)
            XCTAssertFalse(app.scrollViews["continuousPages"].exists)
        }
    }
    @MainActor
    func testDoubleTapAndFitButtonReturnFromZoomToTheWholePage() {
        let app = XCUIApplication(); openEditor(app)
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.pinch(withScale: 2, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ingrandita"), object: canvas)
        wait(for: [zoomed], timeout: 5)
        canvas.doubleTap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina intera"), object: canvas)
        wait(for: [fitted], timeout: 5)
        canvas.doubleTap()
        let widthFitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ingrandita"), object: canvas)
        wait(for: [widthFitted], timeout: 5)
        canvas.doubleTap()
        let toggledBack = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina intera"), object: canvas)
        wait(for: [toggledBack], timeout: 5)
        canvas.doubleTap(); app.buttons["editorFitPage"].tap()
        let fittedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina intera"), object: canvas)
        wait(for: [fittedAgain], timeout: 5)
    }

    @MainActor
    func testHorizontalAndVerticalPageNavigationKeepTheSelectedPageInSync() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorAddPage"].tap()
        XCTAssertTrue(app.buttons["pageSelect-2"].waitForExistence(timeout: 5))
        app.buttons["editorAddPage"].tap()
        XCTAssertTrue(app.buttons["pageSelect-3"].waitForExistence(timeout: 5))
        app.buttons["editorPageNavigation"].tap(); app.buttons["Sfoglia orizzontalmente"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        canvas.swipeRight()
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina corrente"), object: app.buttons["pageSelect-2"])
        wait(for: [previous], timeout: 5)
        canvas.swipeLeft()
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina corrente"), object: app.buttons["pageSelect-3"])
        wait(for: [next], timeout: 5)
        app.buttons["editorPageNavigation"].tap(); app.buttons["Scorrimento verticale"].tap()
        canvas.swipeDown()
        // Continuous deceleration may pass more than one sheet; never require
        // the artificial one-page quantization used by the previous swipe mode.
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Pagina corrente"), object: app.buttons["pageSelect-3"])
        wait(for: [scrolled], timeout: 5)
    }
    @MainActor
    func testPencilTextInputOnPageAndNavigationChoiceAreAvailable() {
        let app = XCUIApplication(); openEditor(app)
        XCTAssertTrue(app.descendants(matching: .any)["pencilCanvas"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["continuousPages"].exists)
        XCTAssertTrue(app.buttons["editorPageNavigation"].exists)
        XCTAssertTrue(app.buttons["editorFitPage"].exists)
        let textTool = app.buttons["tool-Testo con Pencil"]
        XCTAssertTrue(textTool.exists); textTool.tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).tap()
        let input = app.textViews["pageTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("Testo sul foglio")
        app.buttons["pageTextDone"].tap()
        XCTAssertFalse(app.textViews["pageTextInput"].exists)
        app.buttons["editorFitPage"].tap()
    }
    @MainActor
    private func openEditor(_ app: XCUIApplication) {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--reset-ui-storage"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Editor test"); app.buttons["saveNotebookButton"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label == %@", "Editor test")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 5)); notebook.tap()
        let editor = app.buttons["openEditorButton"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let focus = app.buttons["editorFocus"]
        if focus.waitForExistence(timeout: 10), !app.buttons["editorAddText"].exists { focus.tap() }
        XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 10))
    }
    @MainActor
    func testFocusHidesToolbarAndFloatingButtonRestoresIt() {
        let app = XCUIApplication(); openEditor(app)
        let focus = app.buttons["editorFocus"]; XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["editorAddText"])
        wait(for: [hidden], timeout: 5)
        XCTAssertTrue(focus.exists); focus.tap()
        XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFocusEssentialToolsExpandCollapseAndFullToolbarReturns() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorFocus"].tap()
        let mini = app.buttons["editorMiniToolbar"]; XCTAssertTrue(mini.waitForExistence(timeout: 5)); mini.tap()
        XCTAssertTrue(app.buttons["focusTool-pen"].waitForExistence(timeout: 5))
        app.buttons["focusTool-marker"].tap(); XCTAssertFalse(app.buttons["editorAddText"].exists)
        mini.tap(); XCTAssertFalse(app.buttons["focusTool-pen"].exists)
        app.buttons["editorFocus"].tap(); XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMathWorkspaceExposesGeometryFavoritesWithoutLongActionsMenu() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorWorkspace"].tap(); app.buttons["Matematica"].tap(); app.buttons["Fine"].tap()
        XCTAssertTrue(app.buttons["tool-Righello"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tool-Linea"].exists); XCTAssertTrue(app.buttons["tool-Cerchio"].exists)
        app.buttons["tool-Freccia"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pencilCanvas"].exists)
    }

    @MainActor
    func testQuickTextEditUndoRedoAndAccessibleTools() {
        let app = XCUIApplication(); openEditor(app)
        XCTAssertTrue(app.buttons["tool-Penna"].exists); XCTAssertTrue(app.buttons["tool-Oggetti"].exists)
        app.buttons["editorAddText"].tap()
        let text = app.textViews.firstMatch; XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText(" Nota dal test")
        app.buttons["Salva"].firstMatch.tap()
        let undo = app.buttons["editorUndo"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); XCTAssertTrue(undo.isEnabled); undo.tap()
        let redo = app.buttons["editorRedo"]; XCTAssertTrue(redo.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: redo)
        wait(for: [ready], timeout: 5); redo.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    func testSceneRestoresTheOpenNotebookAfterProcessRelaunch() {
        let app = XCUIApplication(); openEditor(app)
        XCTAssertTrue(app.descendants(matching: .any)["pencilCanvas"].waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 15))
    }
    @MainActor
    func testLensInspectorOpensAndClosesWithoutReplacingTheWritingCanvas() {
        let app = XCUIApplication(); openEditor(app)
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5)); let original = canvas.frame
        app.buttons["editorLens"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lensPanelTitle"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(canvas.exists); XCTAssertGreaterThan(canvas.frame.width, 0)
        app.buttons["closeStudyInspector"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(canvas.frame.width - original.width) <= 2 }, object: canvas)
        wait(for: [restored], timeout: 5)
        XCTAssertTrue(app.buttons["editorAddText"].exists)
    }
    @MainActor
    func testWorkspaceProvidesNativePenKindsAndEraserSettings() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorWorkspace"].tap()
        let options = app.buttons["Penne, preset e gomma"]
        XCTAssertTrue(options.waitForExistence(timeout: 5)); options.tap()
        let kind = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tipo")).firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 5)); kind.tap()
        let fountain = app.buttons["Stilografica"]
        if fountain.waitForExistence(timeout: 3) { fountain.tap() }
        else { app.staticTexts["Stilografica"].tap() }
        XCTAssertTrue(app.switches["Solo evidenziatore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Torna alla penna dopo aver cancellato"].exists)
    }
}
