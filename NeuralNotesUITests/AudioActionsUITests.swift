import XCTest

final class AudioActionsUITests: XCTestCase {
    @MainActor
    func testSavedTranscriptHasAReadableFullTextPanel() {
        let app = XCUIApplication(); openAudio(app)
        let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptRead-")).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 5)); read.tap()
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
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.textFields["transcriptTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["transcriptShare"].exists)
    }
    @MainActor
    func testExportOpensOnlyTheShareSheet() {
        let app = XCUIApplication(); openAudio(app)
        let export = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcriptExport-")).firstMatch
        for _ in 0..<4 where !export.exists { app.swipeUp() }
        XCTAssertTrue(export.waitForExistence(timeout: 5)); export.tap()
        XCTAssertTrue(app.descendants(matching: .any)["transcriptShare"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["transcriptTitle"].exists)
    }
}
