import XCTest
import UIKit

final class HandwritingUITests: XCTestCase {
    @MainActor private func open(_ app: XCUIApplication) -> XCUIElement {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        name.typeText("Grafia test"); app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Grafia test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        let focus = app.buttons["editorFocus"]
        if focus.waitForExistence(timeout: 10), !app.buttons["editorAddText"].exists { focus.tap() }
        XCTAssertTrue(app.buttons["editorWorkspace"].waitForExistence(timeout: 8))
        app.buttons["editorWorkspace"].tap()
        let gestures = app.buttons["workspaceGestures"]
        revealWorkspaceRow(gestures, in: app.collectionViews["workspaceList"])
        gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        if finger.value as? String != "1" { finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap() }
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        app.buttons["tool-Penna"].tap()
        for y in [0.3, 0.4, 0.5] {
            canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: y)).press(forDuration: 0.02,
                thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.57, dy: y + 0.035)))
        }
        app.buttons["tool-Oggetti"].tap(); app.buttons["Seleziona tutto"].tap()
        let menu = app.buttons["handwritingMenu"]
        // The selection strip scrolls without changing the page viewport.
        if !menu.isHittable {
            app.scrollViews["selectionActionsScroll"].swipeLeft()
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertTrue(menu.isEnabled)
        return canvas
    }
    @MainActor private func choose(_ command: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["handwritingMenu"].tap()
        app.buttons[command].tap()
        let apply = app.buttons["handwritingApply"]
        let ready = NSPredicate(format: "exists == true AND enabled == true AND isHittable == true")
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: apply)], timeout: 30)
        return apply
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testPreviewCancelAndApplyKeepThePageViewportAndUseOneHistoryAction() {
        let app = XCUIApplication(); let canvas = open(app), frame = canvas.frame
        _ = choose("Raddrizza", in: app)
        let panel = app.descendants(matching: .any)["handwritingPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-straighten-preview")
        app.buttons["handwritingCancel"].tap(); XCTAssertFalse(panel.exists); XCTAssertEqual(canvas.frame, frame)
        let apply = choose("Raddrizza", in: app)
        apply.tap(); XCTAssertFalse(panel.exists)
        let undo = app.buttons["quickUndo"], redo = app.buttons["quickRedo"]
        XCTAssertTrue(undo.isEnabled); undo.tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: redo)], timeout: 10)
        redo.tap()
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-applied-redo")
    }
    @MainActor func testReflowExposesTwoRealHandlesAndAllowsCancelWithoutResizingCanvas() {
        let app = XCUIApplication(); let canvas = open(app), frame = canvas.frame
        _ = choose("Riadatta alla larghezza", in: app)
        let left = app.descendants(matching: .any)["handwritingLeftHandle"].firstMatch
        let right = app.descendants(matching: .any)["handwritingRightHandle"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5)); XCTAssertTrue(right.waitForExistence(timeout: 5))
        let oldX = right.frame.midX
        right.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: right.coordinate(withNormalizedOffset: .init(dx: 3, dy: 0.5)))
        let moved = NSPredicate { _, _ in right.exists && right.frame.midX > oldX + 10 }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: right)], timeout: 5)
        XCTAssertGreaterThan(right.frame.midX, oldX + 10)
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-width-handles")
        app.buttons["handwritingCancel"].tap(); XCTAssertFalse(app.buttons["handwritingApply"].exists)
    }
}
