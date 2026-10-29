import XCTest
import UIKit

final class SnapAndAlignmentUITests: XCTestCase {
    @MainActor func testThreeObjectsExposeAlignmentAndWorkspaceSnapOptions() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Allineamenti")
        app.buttons["saveNotebookButton"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label == %@", "Allineamenti")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 8)); notebook.tap(); app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["Inserisci foto o forma"].tap(); app.buttons["Rettangolo"].tap()
        for x in [0.28, 0.43, 0.61] {
            let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.4))
            let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: x + 0.09, dy: 0.51))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
        app.buttons["tool-Oggetti"].tap(); app.buttons["Seleziona tutto"].tap()
        let alignment = app.buttons["selectionAlignment"]
        XCTAssertTrue(alignment.waitForExistence(timeout: 5))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: alignment)], timeout: 8)
        alignment.tap(); app.buttons["Allinea in alto"].tap()
        let undo = app.buttons["editorUndo"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)], timeout: 8)
        undo.tap()
        let redo = app.buttons["editorRedo"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: redo)], timeout: 8); redo.tap()
        let workspace = app.buttons["editorWorkspace"], toolbar = app.scrollViews["editorToolbarScroll"]
        for _ in 0..<4 where !workspace.isHittable { toolbar.swipeLeft() }
        XCTAssertTrue(workspace.isHittable); workspace.tap()
        let snap = app.buttons["workspaceSnapping"]
        for _ in 0..<4 where !(snap.exists && snap.isHittable) { app.descendants(matching: .any)["workspaceList"].firstMatch.swipeUp() }
        XCTAssertTrue(snap.waitForExistence(timeout: 5)); snap.tap()
        let objects = app.switches["snapObjectsToggle"], grid = app.switches["snapGridToggle"]
        XCTAssertTrue(objects.waitForExistence(timeout: 5)); XCTAssertTrue(grid.exists)
        objects.tap(); XCTAssertEqual(objects.value as? String, "0")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "workspace-snapping"; shot.lifetime = .keepAlways; add(shot)
    }
}
