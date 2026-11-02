import XCTest
import UIKit

final class PDFPerformanceUITests: XCTestCase {
    @MainActor func testImportedDensePDFRemainsVisibleDuringZoomScrollWritingHighlightAndUndo() async throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-pdf-fixture", "--ui-light"]; app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label == %@", "PDF performance test")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 12)); book.tap(); app.buttons["openEditorButton"].tap()
        let canvas = app.descendants(matching: .any)["pencilCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        await settled("Pagina intera", canvas: canvas)
        let originalFrame = canvas.frame
        canvas.pinch(withScale: 4, velocity: 2); await settled("Ingrandita", canvas: canvas)
        canvas.swipeUp(); app.buttons["editorFitPage"].tap(); await settled("Pagina intera", canvas: canvas)
        XCTAssertEqual(canvas.frame.width, originalFrame.width, accuracy: 1); XCTAssertEqual(canvas.frame.height, originalFrame.height, accuracy: 1)

        app.buttons["editorWorkspace"].tap()
        let gestures = app.buttons["Gesti e automatismi"], list = app.collectionViews["workspaceList"]
        for _ in 0..<8 where !(gestures.exists && gestures.isHittable) { list.swipeUp() }
        XCTAssertTrue(gestures.waitForExistence(timeout: 5)); gestures.tap()
        let finger = app.switches["Scrittura con il dito"]; XCTAssertTrue(finger.waitForExistence(timeout: 5))
        finger.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: finger)], timeout: 5)
        app.navigationBars["Gesti e automatismi"].buttons["Workspace"].tap(); app.buttons["Fine"].tap()
        await settled("Pagina intera", canvas: canvas)
        let fit = min((canvas.frame.width - 24) / 600, (canvas.frame.height - 24) / 800)
        let left = canvas.frame.midX - 300 * fit, top = canvas.frame.midY - 400 * fit
        let wordArea = CGRect(x: left + 35 * fit, y: top + 245 * fit, width: 315 * fit, height: 38 * fit)
        let baseline = try await waitForPixels(wordArea, app: app) { $0.black > 60 }
        XCTAssertGreaterThan(baseline.black, 60, "The actual PDF glyphs must be visible, not a blank placeholder")
        app.buttons["tool-Evidenziatore"].tap()
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(.init(dx: left + 42 * fit, dy: top + 265 * fit)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(.init(dx: left + 95 * fit, dy: top + 265 * fit)))
        let marked = try await waitForPixels(wordArea, app: app) { $0.yellow > baseline.yellow + 25 }
        XCTAssertGreaterThan(marked.yellow, baseline.yellow + 25)
        XCTAssertGreaterThanOrEqual(marked.black, Int(Double(baseline.black) * 0.9))
        app.buttons["quickUndo"].tap()
        let restored = try await waitForPixels(wordArea, app: app) { $0.yellow <= baseline.yellow + 10 }
        XCTAssertLessThanOrEqual(restored.yellow, baseline.yellow + 10)
        XCTAssertGreaterThanOrEqual(restored.black, Int(Double(baseline.black) * 0.9))
        app.buttons["tool-Penna"].tap()
        let inkArea = CGRect(x: left + 180 * fit, y: top + 300 * fit, width: 170 * fit, height: 45 * fit)
        let beforeInk = try pixels(inkArea, app: app)
        origin.withOffset(.init(dx: left + 190 * fit, dy: top + 310 * fit)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(.init(dx: left + 335 * fit, dy: top + 330 * fit)))
        let written = try await waitForPixels(inkArea, app: app) { $0.black > beforeInk.black + 30 }
        XCTAssertGreaterThan(written.black, beforeInk.black + 30)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "dense-PDF-zoom-scroll-marker-undo-and-pen"; shot.lifetime = .keepAlways; add(shot)
        let counter = app.buttons["editorPageCounter"]
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: counter)], timeout: 10)
        let settledShot = XCTAttachment(screenshot: app.screenshot()); settledShot.name = "dense-PDF-after-write-settled"; settledShot.lifetime = .keepAlways; add(settledShot)
        app.buttons["quickUndo"].tap()
        let undone = try await waitForPixels(inkArea, app: app) { $0.black <= beforeInk.black + 10 }
        XCTAssertLessThanOrEqual(undone.black, beforeInk.black + 10)
    }
    @MainActor private func settled(_ value: String, canvas: XCUIElement) async {
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND isHittable == true", value), object: canvas)], timeout: 15)
    }
    @MainActor private func waitForPixels(_ box: CGRect, app: XCUIApplication, matching predicate: ((black: Int, yellow: Int)) -> Bool) async throws -> (black: Int, yellow: Int) {
        let deadline = Date().addingTimeInterval(10)
        var result = try pixels(box, app: app)
        while !predicate(result), Date() < deadline { try await Task.sleep(for: .milliseconds(100)); result = try pixels(box, app: app) }
        return result
    }
    @MainActor private func pixels(_ box: CGRect, app: XCUIApplication) throws -> (black: Int, yellow: Int) {
        let screenshot = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage), scale = CGFloat(screenshot.width) / app.frame.width
        let source = try XCTUnwrap(screenshot.cropping(to: box.applying(.init(scaleX: scale, y: scale)).integral))
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let p = buffer.bindMemory(to: UInt8.self)
            var black = 0, yellow = 0
            for i in stride(from: 0, to: p.count, by: 4) {
                if p[i] < 50 && p[i + 1] < 50 && p[i + 2] < 50 { black += 1 }
                if p[i] > 200 && p[i + 1] > 160 && Int(p[i]) - Int(p[i + 2]) > 20 { yellow += 1 }
            }; return (black, yellow)
        }
    }
}
