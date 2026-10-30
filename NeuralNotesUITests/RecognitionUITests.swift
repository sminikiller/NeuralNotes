import XCTest
import UIKit

final class RecognitionUITests: XCTestCase {
    @MainActor func testNativeStrokeAfterRecognizedShapeDeletionNeverRevivesItsRawInk() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-light"]; app.launch()
        let create = app.buttons["newNotebookButton"]; XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let title = app.textFields["notebookNameField"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Riconoscimento nativo")
        app.buttons["saveNotebookButton"].tap()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "Riconoscimento nativo")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 8)); book.tap(); app.buttons["openEditorButton"].tap()
        app.buttons["editorWorkspace"].tap()
        let gestures = app.buttons["Gesti e automatismi"], list = app.collectionViews["workspaceList"]
        for _ in 0..<8 where !(gestures.exists && gestures.isHittable) { list.swipeUp() }
        XCTAssertTrue(gestures.waitForExistence(timeout: 5)); gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        app.buttons["tool-Penna"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        let frame = canvas.frame
        let first = CGRect(x: frame.midX - 60, y: frame.minY + frame.height * 0.45 - 12, width: 120, height: 24)
        let second = first.offsetBy(dx: 0, dy: 90)
        let baseline = try darkPixels(first, app: app)
        draw(first, app: app, hold: 1.0)
        app.buttons["tool-Oggetti"].tap()
        let center = app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: first.midX, dy: first.midY))
        center.tap()
        let handle = app.buttons["shapeHandle-start"]
        XCTAssertTrue(handle.waitForExistence(timeout: 8), "Serve una vera forma riconosciuta, non un semplice tratto di PencilKit.")
        center.press(forDuration: 1)
        let delete = app.buttons["Elimina"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let blank = try await waitForPixels(first, app: app, baseline: baseline, hasInk: false)
        XCTAssertLessThanOrEqual(blank, baseline + 10)
        app.buttons["tool-Penna"].tap(); draw(second, app: app, hold: 0)
        let written = try await waitForPixels(second, app: app, baseline: baseline, hasInk: true)
        XCTAssertGreaterThan(written, baseline + 30)
        XCTAssertLessThanOrEqual(try darkPixels(first, app: app), baseline + 10, "Il nuovo tratto non deve far riapparire l’inchiostro grezzo già convertito.")
        app.buttons["editorUndo"].tap()
        let undone = try await waitForPixels(second, app: app, baseline: baseline, hasInk: false)
        XCTAssertLessThanOrEqual(undone, baseline + 10)
        app.buttons["editorRedo"].tap()
        let restored = try await waitForPixels(second, app: app, baseline: baseline, hasInk: true)
        XCTAssertGreaterThan(restored, baseline + 30)
        XCTAssertLessThanOrEqual(try darkPixels(first, app: app), baseline + 10)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "native-recognition-new-stroke-no-raw-ink"; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func draw(_ box: CGRect, app: XCUIApplication, hold: TimeInterval) {
        let at = app.coordinate(withNormalizedOffset: .zero)
        at.withOffset(.init(dx: box.minX, dy: box.midY)).press(forDuration: 0.05,
            thenDragTo: at.withOffset(.init(dx: box.maxX, dy: box.midY)), withVelocity: .slow, thenHoldForDuration: hold)
    }
    @MainActor private func waitForPixels(_ box: CGRect, app: XCUIApplication, baseline: Int, hasInk: Bool) async throws -> Int {
        let deadline = Date().addingTimeInterval(8)
        var pixels = try darkPixels(box, app: app)
        while Date() < deadline {
            if hasInk ? pixels > baseline + 30 : pixels <= baseline + 10 { return pixels }
            try await Task.sleep(for: .milliseconds(100)); pixels = try darkPixels(box, app: app)
        }; return pixels
    }
    @MainActor private func darkPixels(_ box: CGRect, app: XCUIApplication) throws -> Int {
        let source = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let factor = CGFloat(source.width) / app.frame.width
        let image = try XCTUnwrap(source.cropping(to: box.applying(.init(scaleX: factor, y: factor))))
        var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
            let p = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: p.count, by: 4).filter { p[$0] < 100 && p[$0 + 1] < 100 && p[$0 + 2] < 100 }.count
        }
    }
}
