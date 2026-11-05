import XCTest

final class LayersUITests: XCTestCase {
    @MainActor private func open(_ app: XCUIApplication) {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Livelli test"); app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Livelli test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        let focus = app.buttons["editorFocus"]
        if focus.waitForExistence(timeout: 10), !app.buttons["editorAddText"].exists { focus.tap() }
        XCTAssertTrue(app.buttons["editorLayers"].waitForExistence(timeout: 8))
    }
    @MainActor private func ready(_ app: XCUIApplication) {
        let status = app.descendants(matching: .any)["layerSceneStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pronto"), object: status)], timeout: 12)
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testLayerCreationVisibilityAndUndoRestoreTheActualCanvasOwnerWithoutShrinkingItsFrame() {
        let app = XCUIApplication(); open(app)
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 8)); let size = canvas.frame.size
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Rettangolo"].tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.52, dy: 0.52)))
        app.buttons["editorLayers"].tap()
        let add = app.buttons["layerAdd"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        XCTAssertTrue(app.buttons["Nascondi Livello 2"].waitForExistence(timeout: 8))
        shot(app, "layers-page-panel")
        app.navigationBars["Livelli"].buttons["Chiudi"].tap(); ready(app)
        let badge = app.descendants(matching: .any)["activeLayerBadge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5)); XCTAssertTrue(badge.label.contains("Livello 2"))
        XCTAssertEqual(canvas.frame.width, size.width, accuracy: 2); XCTAssertEqual(canvas.frame.height, size.height, accuracy: 2)
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.48, dy: 0.48)).press(forDuration: 0.05,
            thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.65, dy: 0.65)))
        shot(app, "layers-two-owners-visible")
        app.buttons["editorLayers"].tap(); app.buttons["Nascondi Livello 2"].tap()
        app.navigationBars["Livelli"].buttons["Chiudi"].tap(); ready(app)
        XCTAssertTrue(badge.label.contains("Base")); shot(app, "layers-upper-hidden")
        app.buttons["quickUndo"].tap(); ready(app)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Livello 2"), object: badge)], timeout: 8)
        shot(app, "layers-visibility-undo-owner-restored")
    }
    @MainActor func testLayerMenuRenamesAndOpensAnExplicitSingleOwnerExportWithoutChangingItsVisibility() {
        let app = XCUIApplication(); open(app); app.buttons["editorLayers"].tap()
        let add = app.buttons["layerAdd"]; XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let actions = app.buttons["Azioni Livello 2"]; XCTAssertTrue(actions.waitForExistence(timeout: 8)); actions.tap()
        app.buttons["Rinomina"].tap()
        let field = app.alerts["Nome del livello"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let count = (field.value as? String ?? "").count
        field.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + "Annotazioni")
        app.alerts["Nome del livello"].buttons["Salva"].tap()
        let renamed = app.buttons["Azioni Annotazioni"]; XCTAssertTrue(renamed.waitForExistence(timeout: 8)); renamed.tap()
        app.buttons["Esporta solo questo livello…"].tap()
        XCTAssertTrue(app.navigationBars["Esporta livelli"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Annotazioni"].exists)
        XCTAssertTrue(app.buttons["layerExportApply"].exists)
        XCTAssertFalse(app.switches["Tutto il quaderno"].exists)
        shot(app, "layers-single-owner-export")
        app.navigationBars["Esporta livelli"].buttons["Chiudi"].tap()
        XCTAssertTrue(app.buttons["Nascondi Annotazioni"].waitForExistence(timeout: 5))
    }
}
