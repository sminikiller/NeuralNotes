import XCTest
import UIKit

final class HandwritingUITests: XCTestCase {
    @MainActor private func open(_ app: XCUIApplication) async throws -> XCUIElement {
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
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
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
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertTrue(menu.isEnabled); menu.tap()
        return canvas
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testPreviewCancelAndApplyKeepThePageViewportAndUseOneHistoryAction() async throws {
        let app = XCUIApplication(); let canvas = try await open(app), frame = canvas.frame
        app.buttons["Raddrizza"].tap()
        let panel = app.descendants(matching: .any)["handwritingPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let apply = app.buttons["handwritingApply"]
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)], timeout: 10)
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-straighten-preview")
        app.buttons["handwritingCancel"].tap(); XCTAssertFalse(panel.exists); XCTAssertEqual(canvas.frame, frame)
        app.buttons["handwritingMenu"].tap(); app.buttons["Raddrizza"].tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)], timeout: 10)
        apply.tap(); XCTAssertFalse(panel.exists)
        let undo = app.buttons["quickUndo"], redo = app.buttons["quickRedo"]
        XCTAssertTrue(undo.isEnabled); undo.tap(); XCTAssertTrue(redo.isEnabled); redo.tap()
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-applied-redo")
    }
    @MainActor func testReflowExposesTwoRealHandlesAndAllowsCancelWithoutResizingCanvas() async throws {
        let app = XCUIApplication(); let canvas = try await open(app), frame = canvas.frame
        app.buttons["Riadatta alla larghezza"].tap()
        let apply = app.buttons["handwritingApply"]
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)], timeout: 10)
        let left = app.descendants(matching: .any)["handwritingLeftHandle"].firstMatch
        let right = app.descendants(matching: .any)["handwritingRightHandle"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5)); XCTAssertTrue(right.waitForExistence(timeout: 5))
        let oldX = right.frame.midX
        right.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: right.coordinate(withNormalizedOffset: .init(dx: 3, dy: 0.5)))
        let deadline = Date().addingTimeInterval(5)
        while right.frame.midX <= oldX + 10 && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertGreaterThan(right.frame.midX, oldX + 10)
        XCTAssertEqual(canvas.frame, frame); shot(app, "handwriting-width-handles")
        app.buttons["handwritingCancel"].tap(); XCTAssertFalse(app.buttons["handwritingApply"].exists)
    }
}
