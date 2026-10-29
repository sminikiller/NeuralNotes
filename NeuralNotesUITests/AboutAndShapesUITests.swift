import XCTest
import UIKit

final class AboutAndShapesUITests: XCTestCase {
    @MainActor func testCreditsOpenWithRealVersionInBothOrientationsAndAppearances() {
        continueAfterFailure = false
        let device = XCUIDevice.shared, original = device.orientation
        defer { device.orientation = original == .unknown || original == .faceUp || original == .faceDown ? .portrait : original }
        for (appearance, orientation) in [("Dark", UIDeviceOrientation.portrait), ("Light", .landscapeLeft)] {
            device.orientation = orientation
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--reset-ui-storage", "-AppleInterfaceStyle", appearance]; app.launch()
            let about = app.buttons["libraryAbout"]
            if !about.waitForExistence(timeout: 3) || !about.isHittable { app.buttons["ToggleSidebar"].firstMatch.tap() }
            for _ in 0..<5 where !(about.exists && about.isHittable) { app.swipeUp() }
            XCTAssertTrue(about.waitForExistence(timeout: 8)); about.tap()
            let version = app.staticTexts["aboutVersion"]
            XCTAssertTrue(version.waitForExistence(timeout: 8))
            XCTAssertNotNil(version.label.range(of: #"^Versione [0-9]+\.[0-9]+\.[0-9]+ \(build [0-9]+\)$"#, options: .regularExpression))
            let copy = app.buttons["aboutCopyInformation"]
            XCTAssertTrue(copy.exists); copy.tap()
            let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Informazioni copiate"), object: copy)
            wait(for: [copied], timeout: 5)
            XCTAssertFalse(app.buttons["Invia un feedback"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "credits-\(appearance)"; attachment.lifetime = .keepAlways; add(attachment)
            app.buttons["Chiudi"].tap(); app.terminate()
        }
    }
    @MainActor func testStarCreationSelectionStyleAndUndo() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let title = app.textFields["notebookNameField"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Forme 0.25")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Forme 0.25")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap()
        app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["Inserisci foto o forma"].tap()
        let star = app.buttons["Stella"]; XCTAssertTrue(star.waitForExistence(timeout: 5)); star.tap()
        let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.62))
        a.press(forDuration: 0.05, thenDragTo: b)
        app.buttons["tool-Oggetti"].tap()
        let style = app.buttons["selectionShapeStyle"]
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: style)
        wait(for: [enabled], timeout: 8); style.tap()
        let fill = app.buttons["shapeFillEnabled"]
        for _ in 0..<4 where !(fill.exists && fill.isHittable) { app.swipeUp() }
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        fill.tap()
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Attivo"), object: fill)
        wait(for: [filled], timeout: 5)
        app.buttons["applyShapeStyle"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "star-style-and-handles"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["editorUndo"].tap()
        let redo = app.buttons["editorRedo"]
        let redoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: redo)
        wait(for: [redoReady], timeout: 8); redo.tap()
    }
}
