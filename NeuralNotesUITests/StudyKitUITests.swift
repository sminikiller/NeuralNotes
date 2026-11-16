import XCTest
import UIKit

final class StudyKitUITests: XCTestCase {
    @MainActor func testStudyMapTapeAndReviewAreReachableWithoutChangingPageLayout() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-pdf-fixture", "--ui-light"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "PDF performance test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap(); app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let original = canvas.frame
        func openKit() {
            let insert = app.buttons["editorInsertMenu"]
            XCTAssertTrue(insert.waitForExistence(timeout: 8)); insert.tap()
            let kit = app.buttons["openStudyKit"]
            XCTAssertTrue(kit.waitForExistence(timeout: 5)); kit.tap()
        }
        openKit()
        let add = app.buttons["insertStudyDiagram"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.buttons["quickUndo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickUndo"].isEnabled)
        let map = XCTAttachment(screenshot: app.screenshot()); map.name = "study-connected-map"; map.lifetime = .keepAlways; self.add(map)
        openKit()
        app.segmentedControls.buttons["Ripasso"].tap()
        let tape = app.buttons["insertStudyTape"]
        XCTAssertTrue(tape.waitForExistence(timeout: 5)); tape.tap()
        openKit()
        let start = app.buttons["startStudyReview"]
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let controls = app.descendants(matching: .any)["studyReviewControls"].firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 8))
        app.buttons["Scopri prossima"].tap()
        let review = XCTAttachment(screenshot: app.screenshot()); review.name = "study-review-tape"; review.lifetime = .keepAlways; self.add(review)
        app.buttons["Fine"].tap()
        XCTAssertEqual(canvas.frame.width, original.width, accuracy: 2)
        XCTAssertEqual(canvas.frame.height, original.height, accuracy: 2)
    }
}
