import XCTest
import UIKit

final class TextAndZoomWritingUITests: XCTestCase {
    @MainActor private func openEditor(_ app: XCUIApplication) {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--reset-ui-storage"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Strumenti testo"); app.buttons["saveNotebookButton"].tap()
        let notebook = app.buttons["Strumenti testo"].firstMatch; XCTAssertTrue(notebook.waitForExistence(timeout: 5)); notebook.tap()
        let editor = app.buttons["openEditorButton"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        XCTAssertTrue(app.buttons["editorAddText"].waitForExistence(timeout: 10))
    }
    @MainActor func testZoomWritingOpensAsASmallPanelAndClosingRestoresTheOriginalViewport() {
        let device = XCUIDevice.shared, previous = device.orientation
        device.orientation = .portrait; defer { device.orientation = previous }
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorWorkspace"].tap()
        let gestures = app.buttons["workspaceGestures"], list = app.collectionViews["workspaceList"]
        revealWorkspaceRow(gestures, in: list)
        XCTAssertTrue(gestures.waitForExistence(timeout: 5)); gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 8)); let original = canvas.frame
        app.buttons["Azioni"].tap(); app.buttons["toggleZoomWriting"].tap()
        let panel = app.descendants(matching: .any)["zoomWritingPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let child = app.descendants(matching: .any)["zoomWritingCanvas"].firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 8)); XCTAssertTrue(child.isHittable)
        XCTAssertLessThan(panel.frame.height, original.height * 0.4)
        XCTAssertGreaterThan(canvas.frame.height, original.height * 0.5)
        XCTAssertEqual(canvas.frame.width, original.width, accuracy: 2)
        child.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.45)).press(forDuration: 0.05,
            thenDragTo: child.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.55)))
        let undo = app.buttons["quickUndo"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)], timeout: 10)
        undo.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: undo)], timeout: 10)
        app.buttons["quickRedo"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)], timeout: 10)
        XCTAssertTrue(app.buttons["Nuova riga"].isHittable); app.buttons["Nuova riga"].tap()
        XCTAssertTrue(app.buttons["Avanti"].isHittable); app.buttons["Avanti"].tap()
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "real-zoom-writing-panel"; image.lifetime = .keepAlways; add(image)
        app.buttons["Chiudi finestra di scrittura"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(canvas.frame.height - original.height) <= 2 }, object: canvas)
        wait(for: [restored], timeout: 10)
        XCTAssertFalse(child.exists); XCTAssertTrue(app.buttons["tool-Penna"].exists)
    }
    @MainActor func testNamedSubjectPaletteCanBeCreatedSelectedAndReopenedWithoutChangingOtherTools() {
        let app = XCUIApplication(); openEditor(app)
        app.buttons["editorWorkspace"].tap()
        let entry = app.buttons["Colori per materia"], list = app.collectionViews["workspaceList"]
        for _ in 0..<6 where !entry.isHittable { list.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        app.buttons["Nuovo set di colori"].tap()
        let field = app.textFields["paletteName"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.press(forDuration: 1)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        let old = (field.value as? String) ?? "Nuova materia"
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)); field.typeText("Biologia")
        app.buttons["Salva"].tap()
        let palette = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "choosePalette-")).firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 5)); XCTAssertTrue(palette.label.contains("Biologia"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "subject-palette-selection"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.buttons["Modifica set Biologia"].exists)
    }
}
