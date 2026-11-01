import XCTest
import UIKit

final class ToolCatalogUITests: XCTestCase {
    @MainActor func testNonFavoriteProtractorOpensOptionsOnHoldAndSquaresAreAvailableWithoutChangingFavorites() {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebookNameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Guide e strumenti")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Guide e strumenti")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        XCTAssertFalse(app.buttons["tool-Goniometro"].exists)
        let catalogButton = app.buttons["allWritingTools"]; XCTAssertTrue(catalogButton.waitForExistence(timeout: 8)); catalogButton.tap()
        let catalog = app.scrollViews["toolCatalogScroll"]
        let protractor = app.buttons["catalogTool-protractor"]
        for _ in 0..<8 where !(protractor.exists && protractor.isHittable) { catalog.swipeUp() }
        XCTAssertTrue(protractor.waitForExistence(timeout: 5)); protractor.press(forDuration: 0.6)
        let visible = app.switches["Goniometro visibile"]
        XCTAssertTrue(visible.waitForExistence(timeout: 5)); XCTAssertEqual(visible.value as? String, "1")
        app.segmentedControls.buttons["360°"].tap()
        app.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: 0.85)).tap()
        let guide = app.descendants(matching: .any)["protractorGuide"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        let fullCircle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "360 gradi"), object: guide)
        wait(for: [fullCircle], timeout: 8)
        // A second outside tap closes the catalog if the nested popover kept it open.
        if catalog.exists { app.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: 0.85)).tap() }
        XCTAssertFalse(app.buttons["tool-Goniometro"].exists)
        for raw in ["square45", "square60"] {
            catalogButton.tap()
            let square = app.buttons["catalogTool-\(raw)"]
            for _ in 0..<8 where !(square.exists && square.isHittable) { app.scrollViews["toolCatalogScroll"].swipeUp() }
            XCTAssertTrue(square.waitForExistence(timeout: 5)); square.tap()
            let ruler = app.descendants(matching: .any)["rulerGuide"].firstMatch
            XCTAssertTrue(ruler.waitForExistence(timeout: 8)); XCTAssertGreaterThan(ruler.frame.width, 100)
            XCTAssertFalse(guide.exists && guide.isHittable)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "catalog-squares-without-favorites"; shot.lifetime = .keepAlways; add(shot)
    }
}
