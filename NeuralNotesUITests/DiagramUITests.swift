import XCTest

final class DiagramUITests: XCTestCase {
    @MainActor func testSixLinkedBlocksLabelAndUndoUseRealDiagramState() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-dark"]; app.launch()
        let create = app.buttons["newNotebookButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Diagrammi 0.27")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Diagrammi 0.27")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["Inserisci foto o forma"].tap()
        let rectangle = app.buttons["Rettangolo"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5)); rectangle.tap()
        let start = canvas.coordinate(withNormalizedOffset: .init(dx: 0.4, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: .init(dx: 0.54, dy: 0.52))
        start.press(forDuration: 0.05, thenDragTo: end)
        app.buttons["tool-Oggetti"].tap()
        let summary = app.descendants(matching: .any)["diagramSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        for count in 2...6 {
            let point = app.buttons["diagramCreate-1"]
            XCTAssertTrue(point.waitForExistence(timeout: 5)); XCTAssertTrue(point.isHittable); point.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(count) blocchi, \(count - 1) collegamenti"), object: summary)
            wait(for: [ready], timeout: 8)
        }
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "six-linked-blocks-dark"; screen.lifetime = .keepAlways; add(screen)
        let top = app.buttons["diagramCreate-0"], bottom = app.buttons["diagramCreate-2"]
        XCTAssertTrue(top.exists); XCTAssertTrue(bottom.exists)
        let center = app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: top.frame.midX, dy: (top.frame.midY + bottom.frame.midY) / 2))
        app.buttons["editorUndo"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "5 blocchi, 4 collegamenti"), object: summary)], timeout: 8)
        app.buttons["editorRedo"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "6 blocchi, 5 collegamenti"), object: summary)], timeout: 8)
        // Use the empty interior of the selected unfilled rectangle. It must
        // open its label rather than fitting/zooming the whole page.
        center.doubleTap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Energia conservata")
        app.buttons["diagramLabelSave"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        let saved = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        saved.name = "diagram-rich-label"; saved.lifetime = .keepAlways; add(saved)
    }
}
