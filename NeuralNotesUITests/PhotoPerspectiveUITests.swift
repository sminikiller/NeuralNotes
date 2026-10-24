import XCTest

final class PhotoPerspectiveUITests: XCTestCase {
    @MainActor func testCornersRotationEnhancementAndReopeningKeepAdjustments() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-photo-panel"]; app.launch()
        let corner = app.descendants(matching: .any)["photoCorner-0"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 10))
        let start = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 45, dy: 35)))
        app.buttons["Ruota di 90 gradi a destra"].tap()
        app.buttons["Migliora"].tap()
        app.segmentedControls.buttons["Rettangolo"].tap()
        let confirm = app.buttons["photoCropConfirm"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        wait(for: [ready], timeout: 10)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "photo-perspective-preview"; attachment.lifetime = .keepAlways; add(attachment)
        confirm.tap()
        let result = app.staticTexts["photoTestResult"]; XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Rotazione 1 · migliora sì")
        app.buttons["Riapri foto"].tap(); XCTAssertTrue(corner.waitForExistence(timeout: 5))
        app.buttons["Annulla"].tap(); XCTAssertEqual(result.label, "Rotazione 1 · migliora sì")
    }
}
