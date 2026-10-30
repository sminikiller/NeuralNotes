import XCTest
import UIKit

final class ProtractorUITests: XCTestCase {
    @MainActor func testLongPressKeepsGuideVisibleAndARayIsRealUndoableInk() async throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let title = app.textFields["notebookNameField"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Goniometro")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Goniometro")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        app.buttons["editorWorkspace"].tap(); app.buttons["Matematica"].tap()
        let gestures = app.buttons["Gesti e automatismi"], list = app.collectionViews["workspaceList"]
        for _ in 0..<8 where !(gestures.exists && gestures.isHittable) { list.swipeUp() }
        XCTAssertTrue(gestures.waitForExistence(timeout: 5)); gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        let tool = app.buttons["tool-Goniometro"]; XCTAssertTrue(tool.waitForExistence(timeout: 5)); tool.tap()
        let guide = app.descendants(matching: .any)["protractorGuide"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 8))
        tool.press(forDuration: 0.6)
        XCTAssertTrue(app.switches["Goniometro visibile"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Goniometro visibile"].value as? String, "1", "Tenere premuto deve aprire le opzioni senza spegnere lo strumento.")
        app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.8)).tap()
        let frame = guide.frame
        XCTAssertGreaterThan(frame.width, 100); XCTAssertLessThan(frame.width, app.frame.width)
        let area = CGRect(x: frame.midX + frame.width * 0.10, y: frame.midY - frame.height * 0.25, width: frame.width * 0.15, height: frame.height * 0.15)
        let baseline = try darkPixels(area, app: app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(.init(dx: frame.midX, dy: frame.midY)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(.init(dx: frame.midX + frame.width * 0.3, dy: frame.midY - frame.height * 0.3)))
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "45°"), object: guide)], timeout: 8)
        let drawn = try await waitForPixels(area, app: app, baseline: baseline, ink: true)
        XCTAssertGreaterThan(drawn, baseline + 30)
        app.buttons["editorUndo"].tap()
        let undone = try await waitForPixels(area, app: app, baseline: baseline, ink: false)
        XCTAssertLessThanOrEqual(undone, baseline + 10)
        app.buttons["editorRedo"].tap()
        let redone = try await waitForPixels(area, app: app, baseline: baseline, ink: true)
        XCTAssertGreaterThan(redone, baseline + 30)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "protractor-real-ray-undo-redo"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func waitForPixels(_ box: CGRect, app: XCUIApplication, baseline: Int, ink: Bool) async throws -> Int {
        let deadline = Date().addingTimeInterval(8)
        var pixels = try darkPixels(box, app: app)
        while Date() < deadline {
            if ink ? pixels > baseline + 30 : pixels <= baseline + 10 { return pixels }
            try await Task.sleep(for: .milliseconds(100)); pixels = try darkPixels(box, app: app)
        }
        return pixels
    }
    @MainActor private func darkPixels(_ box: CGRect, app: XCUIApplication) throws -> Int {
        let source = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let scale = CGFloat(source.width) / app.frame.width
        let image = try XCTUnwrap(source.cropping(to: box.applying(.init(scaleX: scale, y: scale))))
        var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 100 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100 }.count
        }
    }
}
