import XCTest
import UIKit

final class PDFStudyUITests: XCTestCase {
    @MainActor private func openEditor() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-pdf-fixture", "--ui-light"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "PDF performance test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap(); app.buttons["openEditorButton"].tap()
        XCTAssertTrue(app.buttons["editorSidePDF"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor func testCompactSidebarLeavesRoomForPDFAndImportsAnImageWithUndo() {
        let app = openEditor(); app.buttons["editorSidePDF"].tap()
        let pdf = app.descendants(matching: .any)["studyPDFView"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        let panel = app.descendants(matching: .any)["pdfStudyPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(pdf.frame.height, panel.frame.height * 0.75, "The PDF must occupy most of the sidebar, not stacked toolbars")
        XCTAssertTrue(app.buttons["studyPDFClip"].isHittable)
        app.buttons["studyPDFClip"].tap()
        let crop = app.descendants(matching: .any)["studyPDFCropOverlay"].firstMatch
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        crop.coordinate(withNormalizedOffset: .init(dx: 0.15, dy: 0.18)).press(forDuration: 0.1,
            thenDragTo: crop.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.45)))
        let undo = app.buttons["quickUndo"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)], timeout: 15)
        XCTAssertFalse(crop.isHittable, "The clipping tool must return to PDF navigation after one selection")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "compact-sidebar-PDF-image-in-notebook"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["closeStudyInspector"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)], timeout: 10)
        XCTAssertTrue(app.buttons["selectionTransfer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["selectionTransfer"].isEnabled)
        undo.tap()
        let redo = app.buttons["quickRedo"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: redo)], timeout: 8)
        redo.tap()
        let restored = XCTAttachment(screenshot: app.screenshot()); restored.name = "PDF-snippet-restored-after-undo"; restored.lifetime = .keepAlways; add(restored)
    }
    @MainActor func testPageScrubberStillNavigatesOnReleaseWithCompactFooter() {
        let app = openEditor()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10)); let original = canvas.frame
        let bar = app.descendants(matching: .any)["editorPageScrubber"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let counter = app.buttons["editorPageCounter"]
        bar.coordinate(withNormalizedOffset: .init(dx: 0.05, dy: 0.5)).press(forDuration: 0.2,
            thenDragTo: bar.coordinate(withNormalizedOffset: .init(dx: 0.99, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 1)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pagina 6 di 6"), object: counter)], timeout: 12)
        XCTAssertEqual(canvas.frame.height, original.height, accuracy: 2)
        XCTAssertEqual(canvas.frame.width, original.width, accuracy: 2)
        // This is the actual 44-point control used by the gesture above. SwiftUI
        // flattens its HStack wrapper and extends the material into the safe area.
        XCTAssertLessThanOrEqual(bar.frame.height, 56)
        XCTAssertGreaterThanOrEqual(bar.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "page-preview-scrubber-after-release"; shot.lifetime = .keepAlways; add(shot)
    }
}
