import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import NeuralNotesCore

final class PageWordsTests: XCTestCase {
    /// Two lines of a page: "Il pensiero critico è pro-" / "pria capacità 12-3".
    private var lines: [PageWord] {
        [PageWord(text: "Il", rect: CGRect(x: 10, y: 100, width: 14, height: 12)),
         PageWord(text: "pensiero", rect: CGRect(x: 28, y: 100, width: 52, height: 12)),
         PageWord(text: "critico", rect: CGRect(x: 84, y: 100, width: 40, height: 12)),
         PageWord(text: "è", rect: CGRect(x: 128, y: 100, width: 6, height: 12)),
         PageWord(text: "pro-", rect: CGRect(x: 138, y: 100, width: 24, height: 12), hyphenated: true),
         PageWord(text: "pria", rect: CGRect(x: 10, y: 116, width: 24, height: 12)),
         PageWord(text: "capacità", rect: CGRect(x: 38, y: 116, width: 50, height: 12)),
         PageWord(text: "12-3", rect: CGRect(x: 92, y: 116, width: 26, height: 12))]
    }

    func testTokensKeepPunctuationAndRememberLineBreaks() {
        let text = "Procedura 12-3,\nvedi  “critico”."
        let tokens = PageWords.tokens(in: text)
        let strings = tokens.map { (text as NSString).substring(with: $0.range) }
        XCTAssertEqual(strings, ["Procedura", "12-3,", "vedi", "“critico”."])
        XCTAssertEqual(tokens.map(\.lineBreakBefore), [false, false, true, false])
        XCTAssertTrue(PageWords.joinsNext("pro-", next: "pria", lineBreak: true))
        XCTAssertFalse(PageWords.joinsNext("pro-", next: "pria", lineBreak: false))
        XCTAssertFalse(PageWords.joinsNext("Nord-", next: "Est", lineBreak: true))
    }

    func testATapAndAnUnderlineFindTheExactWord() {
        let words = lines
        XCTAssertEqual(PageWords.word(at: CGPoint(x: 50, y: 106), in: words), 1)
        XCTAssertEqual(PageWords.word(at: CGPoint(x: 100, y: 113), in: words), 2)
        // Below a word with nothing underneath, where a pen underlines it.
        XCTAssertEqual(PageWords.word(at: CGPoint(x: 150, y: 119), in: words), 4)
        // Inside a word of the second line, not the underline zone of the first.
        XCTAssertEqual(PageWords.word(at: CGPoint(x: 60, y: 121), in: words), 6)
        XCTAssertNil(PageWords.word(at: CGPoint(x: 400, y: 400), in: words))
    }

    func testAHighlighterStrokeSelectsWholeWordsAndJoinsHyphens() throws {
        let words = lines
        let range = try XCTUnwrap(PageWords.range(from: CGPoint(x: 30, y: 113), to: CGPoint(x: 20, y: 128), in: words))
        XCTAssertEqual(range, 1...5)
        XCTAssertEqual(PageWords.text(Array(range), in: words), "pensiero critico è propria")
        XCTAssertEqual(PageWords.lineRects(Array(range), in: words).count, 2)
        // Backwards strokes select the same words.
        XCTAssertEqual(PageWords.range(from: CGPoint(x: 20, y: 128), to: CGPoint(x: 30, y: 113), in: words), 1...5)
        XCTAssertEqual(PageWords.text([4], in: words), "pro-")
    }

    func testLassoAndRectangleTakeOnlyWholeWordsWithTheirCenterInside() {
        let words = lines
        let loop = [CGPoint(x: 80, y: 95), CGPoint(x: 170, y: 95), CGPoint(x: 170, y: 113), CGPoint(x: 80, y: 113)]
        XCTAssertEqual(PageWords.inside(polygon: loop, in: words), [2, 3, 4])
        XCTAssertEqual(PageWords.inside(rect: CGRect(x: 0, y: 112, width: 100, height: 20), in: words), [5, 6])
        XCTAssertTrue(PageWords.inside(polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], in: words).isEmpty)
    }

    func testAStrokeIsAHighlighterALoopIsALassoAndAreaModeUsesTheShape() {
        let words = lines
        // A flat stroke under "pensiero critico".
        let flat = [CGPoint(x: 30, y: 113), CGPoint(x: 60, y: 113.5), CGPoint(x: 100, y: 113)]
        XCTAssertEqual(PageWords.pick(trace: flat, in: words, area: false), [1, 2])
        // A loop around both lines selects only the words inside it.
        let loop = [CGPoint(x: 30, y: 96), CGPoint(x: 95, y: 96), CGPoint(x: 95, y: 130), CGPoint(x: 30, y: 130), CGPoint(x: 31, y: 97)]
        XCTAssertEqual(PageWords.pick(trace: loop, in: words, area: false), [1, 6])
        // In area mode an open diagonal drag takes the words inside its rectangle.
        let drag = [CGPoint(x: 0, y: 95), CGPoint(x: 60, y: 110), CGPoint(x: 90, y: 132)]
        XCTAssertEqual(PageWords.pick(trace: drag, in: words, area: true), [0, 1, 5, 6])
        XCTAssertTrue(PageWords.pick(trace: [], in: words, area: false).isEmpty)
    }

    func testSearchMatchesIgnoreCaseAndAccentsAndCrossWordsAndHyphens() {
        let words = lines
        XCTAssertEqual(PageWords.matches("PENSIERO critico", in: words), [[1, 2]])
        XCTAssertEqual(PageWords.matches("capacita", in: words), [[6]])
        XCTAssertEqual(PageWords.matches("propria", in: words), [[4, 5]])
        XCTAssertEqual(PageWords.matches("12-3", in: words), [[7]])
        XCTAssertTrue(PageWords.matches("assente", in: words).isEmpty)
        XCTAssertTrue(PageWords.matches("  ", in: words).isEmpty)
    }

    func testDisjointWordsNeverHighlightAnUnselectedWordAndInvalidIDsAreIgnored() {
        let words = lines
        let marks = PageWords.lineRects([0, 2, 2, -1, 900], in: words)
        XCTAssertEqual(marks, [words[0].rect, words[2].rect])
        XCTAssertEqual(PageWords.text([2, 0, 2, -1, 900], in: words), "Il critico")
        let unicode = "🙂 terapia\r\nè utile"
        let tokens = PageWords.tokens(in: unicode)
        XCTAssertEqual(tokens.map { (unicode as NSString).substring(with: $0.range) }, ["🙂", "terapia", "è", "utile"])
        XCTAssertEqual(tokens.map(\.lineBreakBefore), [false, false, true, false])
    }
}

final class LensMarkupTests: XCTestCase {
    func testListsBoldAndNumberedStepsBecomeBlocks() {
        let text = "La **fotosintesi** avviene nei cloroplasti.\n\n- luce\n- *acqua*\n1. assorbimento\n2) sintesi\n# Nota"
        let blocks = LensMarkup.blocks(text)
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0], .paragraph([LensMarkup.Span(text: "La "), LensMarkup.Span(text: "fotosintesi", bold: true), LensMarkup.Span(text: " avviene nei cloroplasti.")]))
        XCTAssertEqual(blocks[1], .bullet([LensMarkup.Span(text: "luce")]))
        XCTAssertEqual(blocks[2], .bullet([LensMarkup.Span(text: "acqua", italic: true)]))
        XCTAssertEqual(blocks[3], .numbered("1.", [LensMarkup.Span(text: "assorbimento")]))
        XCTAssertEqual(blocks[4], .numbered("2.", [LensMarkup.Span(text: "sintesi")]))
        XCTAssertEqual(blocks[5], .heading([LensMarkup.Span(text: "Nota")]))
        XCTAssertEqual(LensMarkup.plain(text), "La fotosintesi avviene nei cloroplasti.\n• luce\n• acqua\n1. assorbimento\n2. sintesi\nNota")
    }

    func testUnpairedMarkersAndPlainSentencesStayAsWritten() {
        XCTAssertEqual(LensMarkup.spans("2 * 3 = 6"), [LensMarkup.Span(text: "2 * 3 = 6")])
        XCTAssertEqual(LensMarkup.spans("**solo inizio"), [LensMarkup.Span(text: "**solo inizio")])
        XCTAssertEqual(LensMarkup.blocks("Nel 1848 ci furono i moti."), [.paragraph([LensMarkup.Span(text: "Nel 1848 ci furono i moti.")])])
        XCTAssertEqual(LensMarkup.blocks("12.5 metri"), [.paragraph([LensMarkup.Span(text: "12.5 metri")])])
        // The note's own text, as edited: bullets and steps written with a tab.
        XCTAssertEqual(LensMarkup.blocks("•\tluce\n1.\tpasso"), [.bullet([LensMarkup.Span(text: "luce")]), .numbered("1.", [LensMarkup.Span(text: "passo")])])
    }
}

final class PDFTextIndexTests: XCTestCase {
    func testLargePDFPagesGetTheirTextLayerIndexedInOneWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), document = UUID(), book = UUID()
        try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        var first = try await workspace.addPage(); var second = try await workspace.addPage(); _ = try await workspace.addPage()
        first.pdfFile = "media/libro.pdf"; first.pdfIndex = 0; first.revision += 1; first = try await workspace.save(first, drawing: Data([1]))
        second.pdfFile = "media/libro.pdf"; second.pdfIndex = 1; second.revision += 1; second = try await workspace.save(second, drawing: Data([1]))
        let missing = try await workspace.pagesNeedingPDFText()
        XCTAssertEqual(Set(missing.map(\.id)), [first.id, second.id])
        let stored = try await workspace.storePDFText([(first.id, first.revision, "Procedura 12-3 per la medicazione"),
                                                       (second.id, second.revision + 5, "revisione sbagliata")])
        XCTAssertEqual(stored, 1)
        let remaining = try await workspace.pagesNeedingPDFText()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let chunks = try await workspace.indexedChunks()
        let hit = try XCTUnwrap(chunks.first { $0.text.contains("12-3") })
        XCTAssertEqual(hit.reference.pageID, first.id); XCTAssertEqual(hit.kind, .pdf)
    }

    func testEmptyPDFProbePersistsButDoesNotPreventLaterOCR() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), document = UUID(), book = UUID()
        try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        var page = try await workspace.addPage()
        page.pdfFile = "media/scansione.pdf"; page.pdfIndex = 0; page.revision += 1
        page = try await workspace.save(page, drawing: Data([1]))
        let stored = try await workspace.storePDFText([(page.id, page.revision, "")])
        XCTAssertEqual(stored, 1)
        let reopened = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        let missing = try await reopened.pagesNeedingPDFText()
        let needsOCR = await reopened.needsAutomaticOCR(pageID: page.id, revision: page.revision)
        XCTAssertTrue(missing.isEmpty); XCTAssertTrue(needsOCR)
        let recognized = try await reopened.storeAutomaticOCR(pageID: page.id, revision: page.revision, text: "La scansione ora è ricercabile")
        XCTAssertTrue(recognized)
        let chunks = try await reopened.indexedChunks()
        XCTAssertTrue(chunks.contains { $0.text.contains("ricercabile") && $0.kind == .pdf })
        let done = await reopened.needsAutomaticOCR(pageID: page.id, revision: page.revision)
        XCTAssertFalse(done)
        page.revision += 1; page = try await reopened.save(page, drawing: Data([2]))
        let stale = try await reopened.pagesNeedingPDFText()
        XCTAssertEqual(stale.map(\.id), [page.id])
    }
}
