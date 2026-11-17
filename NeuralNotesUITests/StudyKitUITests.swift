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
        let catalog = app.buttons["allWritingTools"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 8))
        catalog.tap()
        let catalogStudy = app.buttons["catalogStudyKit"]
        XCTAssertTrue(catalogStudy.waitForExistence(timeout: 5))
        catalogStudy.tap()
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

    @MainActor func testEditorControlsAlignAndFocusUsesTheBottomEdge() {
        continueAfterFailure = false
        let device = XCUIDevice.shared, previous = device.orientation
        device.orientation = .landscapeLeft
        defer { device.orientation = previous }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-pdf-fixture", "--ui-dark"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "PDF performance test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap(); app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        let undo = app.buttons["quickUndo"], redo = app.buttons["quickRedo"], focus = app.buttons["editorFocus"]
        let pen = app.buttons["tool-Penna"], toolbar = app.scrollViews["editorToolbarScroll"]
        let workspace = app.buttons["editorWorkspace"], library = app.buttons["editorReturnToLibrary"]
        let scrubber = app.descendants(matching: .any)["editorPageScrubber"].firstMatch
        let strip = app.descendants(matching: .any)["editorPageStrip"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let normalReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pen.isHittable && focus.isHittable && abs(pen.frame.midY - focus.frame.midY) <= 2
                && abs(undo.frame.midY - focus.frame.midY) <= 2
                && toolbar.frame.maxX <= focus.frame.minX
        }, object: focus)
        wait(for: [normalReady], timeout: 10)
        XCTAssertEqual(redo.frame.midY, focus.frame.midY, accuracy: 2)
        capture("editor-aligned-chrome", app)
        // The canvas AX wrapper includes the navigation bar's scroll-edge inset.
        XCTAssertLessThanOrEqual(undo.frame.minY - canvas.frame.minY, 24)
        XCTAssertLessThan(workspace.frame.minX, toolbar.frame.maxX)
        XCTAssertLessThanOrEqual(library.frame.minY - app.frame.minY, 12)
        XCTAssertEqual(strip.frame.maxY, app.frame.maxY, accuracy: 2)
        // Keep the touch target close to the edge while leaving room for the Home gesture.
        let bottomClearance = app.frame.maxY - scrubber.frame.maxY
        XCTAssertGreaterThanOrEqual(bottomClearance, 6)
        XCTAssertLessThanOrEqual(bottomClearance, 16)

        let previousHeight = canvas.frame.height
        focus.tap()
        let focusReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !pen.exists && abs(undo.frame.midY - focus.frame.midY) <= 2
                && canvas.frame.height > previousHeight + 40
                && abs(canvas.frame.minY - app.frame.minY) <= 2
                && abs(canvas.frame.maxY - app.frame.maxY) <= 2
        }, object: focus)
        wait(for: [focusReady], timeout: 10)
        app.buttons["editorMiniToolbar"].tap()
        let studio = app.buttons["focusStudyKit"]
        XCTAssertTrue(studio.waitForExistence(timeout: 5))
        XCTAssertEqual(studio.frame.midY, undo.frame.midY, accuracy: 2)
        capture("editor-focus-aligned-chrome", app)
        studio.tap()
        XCTAssertTrue(app.buttons["insertStudyDiagram"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
