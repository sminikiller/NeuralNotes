import XCTest

final class AudioActionsUITests: XCTestCase {
    @MainActor
    func testSavedTranscriptHasAReadableFullTextPanel() {
        let app = XCUIApplication(); openAudio(app)
        let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptRead-")).firstMatch
        reveal(read, in: app); read.tap()
        XCTAssertTrue(app.scrollViews["transcriptReader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Testo da esportare"].exists)
        XCTAssertFalse(app.textFields["transcriptTitle"].exists)
    }
    @MainActor
    private func openAudio(_ app: XCUIApplication) {
        continueAfterFailure = false
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
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.textFields["transcriptTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["transcriptShare"].exists)
    }
    @MainActor
    func testExportOpensOnlyTheShareSheet() {
        let app = XCUIApplication(); openAudio(app)
        let export = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptExport-")).firstMatch
        reveal(export, in: app); export.tap()
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
        let organize = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "audioOrganize-")).firstMatch
        reveal(organize, in: app); organize.tap()
        let archive = app.buttons["Archivia"]; XCTAssertTrue(archive.waitForExistence(timeout: 3)); archive.tap()
        let scope = app.segmentedControls["audioLibraryScope"]
        reveal(scope, in: app, upwards: false); scope.buttons["Archivio"].tap()
        reveal(organize, in: app); organize.tap()
        let restore = app.buttons["Sposta nei recenti"]; XCTAssertTrue(restore.waitForExistence(timeout: 3)); restore.tap()
        reveal(scope, in: app, upwards: false); scope.buttons["Recenti"].tap()
        let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptRead-")).firstMatch
        reveal(read, in: app); read.tap()
        XCTAssertTrue(app.scrollViews["transcriptReader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Testo da esportare"].exists)
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        if !element.exists || !element.isHittable {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
}
