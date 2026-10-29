import XCTest
import UIKit

final class AudioActionsUITests: XCTestCase {
    @MainActor
    func testSavedTranscriptHasAReadableFullTextPanel() {
        let app = XCUIApplication(); openAudio(app)
        let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptRead-")).firstMatch
        reveal(read, in: app).tap()
        XCTAssertTrue(app.scrollViews["transcriptReader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Testo da esportare"].exists)
        XCTAssertFalse(app.textFields["transcriptTitle"].exists)
    }
    @MainActor
    private func openAudio(_ app: XCUIApplication) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--ui-testing", "--reset-ui-storage", "--ui-audio-fixture"]; app.launch()
        let notebook = app.buttons.matching(NSPredicate(format: "label == %@", "Audio UI test")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 10)); notebook.tap()
        let editor = app.buttons["openEditorButton"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let focus = app.buttons["editorFocus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 10))
        if !app.buttons["editorAudio"].exists { focus.tap() }
        let audio = app.buttons["editorAudio"]; XCTAssertTrue(audio.waitForExistence(timeout: 5)); audio.tap()
    }
    @MainActor
    func testEditOpensOnlyTheTranscriptEditor() {
        let app = XCUIApplication(); openAudio(app)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptEdit-")).firstMatch
        reveal(edit, in: app).tap()
        XCTAssertTrue(app.textFields["transcriptTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["transcriptShare"].exists)
    }
    @MainActor
    func testExportOpensOnlyTheShareSheet() {
        let app = XCUIApplication(); openAudio(app)
        let export = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptExport-")).firstMatch
        reveal(export, in: app).tap()
        // The system share UI can be in-process or a remote extension. Both
        // variants are visible in the exported AX evidence from iPadOS 18.5.
        let activity = app.otherElements.matching(NSPredicate(format: "identifier IN %@", ["ActivityListView", "ShareSheet.RemoteContainerView"])).firstMatch
        let visible = activity.waitForExistence(timeout: 10)
        if !visible {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(visible)
        XCTAssertFalse(app.textFields["transcriptTitle"].exists)
    }
    @MainActor
    func testArchivedTranscriptCanBeFoundAndMovedBackToRecent() {
        let app = XCUIApplication(); openAudio(app)
        let organize = app.collectionViews["audioLibraryList"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "audioOrganize-")).firstMatch
        openOrganization(organize, in: app)
        let archive = app.buttons["Archivia"]; XCTAssertTrue(archive.waitForExistence(timeout: 3)); archive.tap()
        selectScope("Archivio", index: 1, in: app)
        openOrganization(organize, in: app)
        let restore = app.buttons["Sposta nei recenti"]; XCTAssertTrue(restore.waitForExistence(timeout: 3)); restore.tap()
        selectScope("Recenti", index: 0, in: app)
        let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptRead-")).firstMatch
        reveal(read, in: app).tap()
        XCTAssertTrue(app.scrollViews["transcriptReader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Testo da esportare"].exists)
    }
    @MainActor private func selectScope(_ title: String, index: Int, in app: XCUIApplication) {
        let scope = app.segmentedControls["audioLibraryScope"]
        reveal(scope, in: app, upwards: false)
        scope.coordinate(withNormalizedOffset: CGVector(dx: (Double(index) + 0.5) / 3, dy: 0.5)).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: scope.buttons[title])
        wait(for: [selected], timeout: 5)
    }
    @MainActor
    private func openOrganization(_ menu: XCUIElement, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let list = app.collectionViews["audioLibraryList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<14 {
            let top = list.frame.minY + 120, bottom = list.frame.maxY - 24
            if menu.exists && menu.frame.midY > top && menu.frame.midY < bottom {
                XCTAssertTrue(menu.isEnabled, file: file, line: line)
                // UIKit exposes this SwiftUI Menu through two nested AX buttons;
                // both report non-hittable. Use the observed visible control's
                // centre and assert the actual Archive/Restore menu afterwards.
                menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return
            }
            let down = menu.exists && menu.frame.height > 0 && menu.frame.midY < top
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.5 : 0.76)).press(forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.76 : 0.5)))
        }
        XCTFail("Organizzazione audio non visibile nella lista", file: file, line: line)
    }

    @MainActor @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        func target() -> XCUIElement {
            // SwiftUI Menu exposes a non-interactive AX wrapper containing the
            // actual native button. Tap that child, not the wrapper's identifier.
            if element.exists && !element.isHittable {
                let native = element.buttons.firstMatch
                if native.exists { return native }
            }
            return element
        }
        let list = app.collectionViews["audioLibraryList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), file: file, line: line)
        // A row can be reported hittable while clipped by a popover/navigation bar.
        // Scroll only this list, with short drags and direction correction after overshoot.
        for _ in 0..<18 {
            let actual = target()
            let visible = list.frame.insetBy(dx: 12, dy: 0)
            let top = visible.minY + 120, bottom = visible.maxY - 24
            if actual.exists && actual.isHittable && actual.frame.midY > top && actual.frame.midY < bottom { return actual }
            let down = element.exists && element.frame.height > 0 ? element.frame.midY < top : !upwards
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.5 : 0.76))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.76 : 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !element.exists || !element.isHittable {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let actual = target()
        XCTAssertTrue(actual.isHittable, file: file, line: line)
        XCTAssertGreaterThan(actual.frame.midY, list.frame.minY + 120, file: file, line: line)
        XCTAssertLessThan(actual.frame.midY, list.frame.maxY - 24, file: file, line: line)
        return actual
    }
}
