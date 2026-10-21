import XCTest
@testable import NeuralNotesCore

final class PageAndTranscriptTests: XCTestCase {
    func testExplicitPartialStateAndCorrectionsOverrideAStaleNonemptyProjection() {
        var session = AudioSession(title: "Importata")
        session.transcript = [TranscriptSegment(start: 10, duration: 1, text: "Proiezione precedente"), TranscriptSegment(start: 70, duration: 1, text: "Secondo minuto")]
        XCTAssertTrue(session.hasCompletedTranscript) // Legacy catalogs had no flag.
        session.transcriptionComplete = false
        XCTAssertFalse(session.hasCompletedTranscript)
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: "Correzione autorevole")]
        XCTAssertEqual(session.readableTranscript.map(\.text), ["Correzione autorevole", "Secondo minuto"])
        session.transcriptionComplete = true; XCTAssertTrue(session.hasCompletedTranscript)
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: ""), TranscriptCorrection(start: 60, text: "")]
        XCTAssertFalse(session.hasTranscriptText); XCTAssertFalse(session.hasCompletedTranscript)
    }
    func testNormalWritingProgressingRightWithRepeatedAscendersIsNotAScratch() {
        let points = (0...400).map { i -> StrokeSample in
            StrokeSample(x: Double(i) / 4.0, y: sin(Double(i) * 16.0 * Double.pi / 400.0) * 10.0)
        }
        XCTAssertFalse(ScratchGesture.matches(points))
    }
    func testScratchAcceptsRepeatedVerticalPassesAndBlackeningLoopsButNotOneLoop() {
        let vertical = (0..<12).map { StrokeSample(x: Double($0), y: $0 % 2 == 0 ? 0 : 50) }
        XCTAssertTrue(ScratchGesture.matches(vertical))
        let oneLoop = (0...100).map { i -> StrokeSample in
            let angle = Double(i) * 2.0 * Double.pi / 100.0
            return StrokeSample(x: 50 * cos(angle), y: 15 * sin(angle))
        }
        XCTAssertFalse(ScratchGesture.matches(oneLoop))
        let blackening = (0...400).map { i -> StrokeSample in
            let angle = Double(i) * 8.0 * Double.pi / 400.0
            return StrokeSample(x: 50 * cos(angle), y: 15 * sin(angle))
        }
        XCTAssertTrue(ScratchGesture.matches(blackening))
    }

    func testReadableTranscriptRecoversChunksAndHonorsCorrections() {
        var session = AudioSession(title: "Recuperata")
        session.transcriptionComplete = true
        session.transcriptionChunks = [TranscriptionChunk(file: "audio/a.caf", window: SpeechWindow(start: 0, duration: 45), language: "it-IT",
            segments: [TranscriptSegment(start: 1, duration: 1, text: "Originale")])]
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: "Corretto")]
        XCTAssertTrue(session.hasCompletedTranscript)
        XCTAssertEqual(session.readableTranscript.map(\.text), ["Corretto"])
        session.transcriptCorrections = [TranscriptCorrection(start: 0, text: "")]
        XCTAssertFalse(session.hasTranscriptText)
        XCTAssertFalse(session.hasCompletedTranscript)
    }

    func testEmptyCompletedRecognitionIsNotSavedTextAndWhitespaceIsNotDisplayed() {
        var session = AudioSession(title: "Silenzio"); session.transcriptionComplete = true
        session.transcript = [TranscriptSegment(start: 0, duration: 1, text: "  \n")]
        XCTAssertFalse(session.hasTranscriptText); XCTAssertFalse(session.hasCompletedTranscript)
        XCTAssertTrue(TranscriptText.minutes(session.transcript).isEmpty)
    }
    func testInvalidPaperSpacingCannotReplaceAReadableSavedPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let original = try await workspace.addDefaultPage()
        var invalid = original; invalid.revision = 1; invalid.appearance = PaperAppearance(); invalid.appearance?.spacing = 0
        do { _ = try await workspace.save(invalid, drawing: Data([1])); XCTFail("Invalid spacing accepted") } catch { }
        let pages = try await workspace.pages(); XCTAssertEqual(pages, [original])
    }

    func testTwoHourRecordingIsCoveredWithoutGapsOrOverlaps() {
        let duration = 7200.25
        let windows = SpeechWindow.plan(duration: duration, maximum: 45)
        XCTAssertEqual(windows.count, 161)
        XCTAssertEqual(windows.first?.start, 0)
        XCTAssertEqual(windows.last?.duration, 0.25)
        XCTAssertEqual(windows.reduce(0) { $0 + $1.duration }, duration, accuracy: 0.0001)
        for pair in zip(windows, windows.dropFirst()) { XCTAssertEqual(pair.0.start + pair.0.duration, pair.1.start, accuracy: 0.0001) }
        XCTAssertTrue(SpeechWindow.plan(duration: .infinity).isEmpty)
        XCTAssertTrue(SpeechWindow.plan(duration: -1).isEmpty)
    }
    func testMinuteExportSortsAndKeepsHourAndPartialStatus() {
        let segments = [TranscriptSegment(start: 3605, duration: 1, text: "Seconda ora"),
            TranscriptSegment(start: 65, duration: 1, text: "seguito"), TranscriptSegment(start: 61, duration: 1, text: "Primo")]
        let text = TranscriptText.export(title: "Fisica", segments: segments, complete: false)
        XCTAssertTrue(text.contains("Trascrizione parziale"))
        XCTAssertTrue(text.contains("[00:01:00] Primo seguito")); XCTAssertTrue(text.contains("[01:00:00] Seconda ora"))
    }
    func testManualCorrectionSurvivesLaterChunksWithoutDuplicatingTheMinute() {
        let raw = [TranscriptSegment(start: 2, duration: 1, text: "errato"),
            TranscriptSegment(start: 46, duration: 1, text: "altro"), TranscriptSegment(start: 95, duration: 1, text: "successivo")]
        let result = TranscriptText.corrected(raw, corrections: [TranscriptCorrection(start: 0, text: "Corretto")])
        XCTAssertEqual(result.map(\.text), ["Corretto", "successivo"])
        XCTAssertEqual(result.map(\.start), [0, 95])
    }
    func testPageTemplateKeepsAppearanceAndOrientationThroughJSON() throws {
        let template = PageTemplate(paper: .dotted, appearance: PaperAppearance(tone: .cream, spacing: 30, margin: true), format: .a4, landscape: true)
        let copy = try JSONDecoder().decode(PageTemplate.self, from: JSONEncoder().encode(template))
        let page = copy.makePage()
        XCTAssertEqual(page.paper, .dotted); XCTAssertEqual(page.appearance?.tone, .cream)
        XCTAssertEqual(page.appearance?.spacing, 30); XCTAssertGreaterThan(page.width, page.height)
    }
    func testNewDefaultPageUsesNotebookTemplateAndIndependentIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest, template: PageTemplate(paper: .grid, appearance: PaperAppearance(tone: .mint)))
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let first = try await workspace.addDefaultPage(), second = try await workspace.addDefaultPage()
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(first.appearance?.tone, .mint); XCTAssertEqual(second.paper, .grid)
    }
    func testScratchDistinguishesRepeatedZigZagFromStraightAndCircularStrokes() {
        var scratch: [StrokeSample] = []
        for i in 0..<16 { scratch.append(StrokeSample(x: i % 2 == 0 ? 0 : 100, y: Double(i))) }
        XCTAssertTrue(ScratchGesture.matches(scratch))
        let line = (0..<20).map { StrokeSample(x: Double($0 * 10), y: 10) }
        XCTAssertFalse(ScratchGesture.matches(line))
        let circle = (0..<60).map { i -> StrokeSample in
            let angle: Double = Double(i) * 2.0 * Double.pi / 59.0
            return StrokeSample(x: cos(angle) * 50, y: sin(angle) * 50)
        }
        XCTAssertFalse(ScratchGesture.matches(circle))
    }
    func testSmallScratchRecognizesDirectionChangesAcrossDenseSamples() {
        var points: [StrokeSample] = []
        for pass in 0..<8 {
            for i in 0..<41 {
                let x = Double(pass % 2 == 0 ? i : 40 - i) * 0.5
                points.append(StrokeSample(x: x, y: Double(pass)))
            }
        }
        XCTAssertTrue(ScratchGesture.matches(points))
    }
}
