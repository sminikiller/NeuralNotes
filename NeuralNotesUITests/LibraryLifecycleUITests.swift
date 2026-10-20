import XCTest

final class LibraryLifecycleUITests: XCTestCase {
    @MainActor
    func testNotebookSurvivesRenameAndProcessRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage"]
        app.launch()
        let newNotebook = app.buttons["newNotebookButton"]
        XCTAssertTrue(newNotebook.waitForExistence(timeout: 10))
        newNotebook.tap()
        let name = app.textFields["notebookNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Fisica")
        app.buttons["saveNotebookButton"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label == %@", "Fisica")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 5))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "documentIntegrityStatus")
            .firstMatch.waitForExistence(timeout: 5))
        app.buttons["editOpenedNotebookButton"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Fisica II")
        app.buttons["saveNotebookButton"].tap()
        let renamed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Fisica II"),
                                                object: app.staticTexts["openedNotebookTitle"])
        wait(for: [renamed], timeout: 5)
        XCTAssertEqual(app.staticTexts["openedNotebookTitle"].label, "Fisica II")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let reopened = app.buttons.matching(NSPredicate(format: "label == %@", "Fisica II")).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        reopened.tap()
        XCTAssertTrue(app.staticTexts["openedNotebookTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["openedNotebookTitle"].label, "Fisica II")
    }
}
