import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import NeuralNotesCore

final class LensNotesTests: XCTestCase {
    private func note(_ title: String, body: String, at point: CGPoint, source: LensNoteSource? = nil, collapsed: Bool = false) -> TextElement {
        let origin = "Lente AI · concetto · conoscenza generale, non dalle tue fonti"
        var text = TextElement(text: LensNotes.text(title: title, body: body, origin: origin))
        text.x = Double(point.x); text.y = Double(point.y); text.width = 260; text.fontSize = 14
        text.lensNote = LensNoteInfo(title: title, origin: origin, source: source, collapsed: collapsed, createdAt: 10)
        return text
    }

    func testOlderTextBoxesDecodeWithoutANoteAndNotesSurviveARoundTrip() throws {
        let plain = try JSONEncoder().encode(TextElement(text: "Appunto"))
        XCTAssertNil(try JSONDecoder().decode(TextElement.self, from: plain).lensNote)
        let page = UUID()
        let value = note("Fotosintesi", body: "Processo delle piante.", at: CGPoint(x: 40, y: 50),
                         source: LensNoteSource(pageID: page, rect: CGRect(x: 10, y: 20, width: 100, height: 30)), collapsed: true)
        let decoded = try JSONDecoder().decode(TextElement.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.lensNote, value.lensNote)
        XCTAssertEqual(decoded.lensNote?.source?.rect, CGRect(x: 10, y: 20, width: 100, height: 30))
        XCTAssertTrue(decoded.lensNote?.isCollapsed == true)
        XCTAssertNil(LensNoteInfo(title: "Aperta").collapsed)
    }

    func testIndexListsNotesPageByPageTopToBottomWithTheirEditableBody() {
        var first = PageSnapshot(), second = PageSnapshot()
        first.texts = [note("Seconda", body: "Riga uno\nRiga due", at: CGPoint(x: 10, y: 300)), TextElement(text: "Testo normale"),
                       note("Prima", body: "In alto", at: CGPoint(x: 400, y: 20), collapsed: true)]
        second.texts = [note("Terza", body: "Altra pagina", at: CGPoint(x: 0, y: 0))]
        let notes = LensNotes.index([first, second])
        XCTAssertEqual(notes.map(\.title), ["Prima", "Seconda", "Terza"])
        XCTAssertEqual(notes.map(\.pageNumber), [1, 1, 2])
        XCTAssertEqual(notes[0].collapsed, true); XCTAssertEqual(notes[1].collapsed, false)
        XCTAssertEqual(notes[1].body, "Riga uno\nRiga due")
        XCTAssertEqual(notes[2].pageID, second.id)
        var edited = first.texts[0]; edited.text = "Titolo cambiato a mano\nSolo corpo"
        XCTAssertEqual(LensNotes.body(of: edited), "Titolo cambiato a mano\nSolo corpo")
        XCTAssertEqual(LensNotes.text(title: " Titolo ", body: "", origin: nil), "Titolo")
    }

    func testControlsStayOnThePageAndTheLinkAppearsOnlyWhenApart() {
        let control = LensNotes.reduceControl(note: CGRect(x: 700, y: 0, width: 60, height: 40), pageWidth: 768, pageHeight: 1024)
        XCTAssertGreaterThanOrEqual(control.minY, 0); XCTAssertLessThanOrEqual(control.maxX, 768)
        XCTAssertEqual(LensNotes.badge(x: 5, y: 6), CGRect(x: 5, y: 6, width: 30, height: 30))
        XCTAssertNil(LensNotes.connector(note: CGRect(x: 0, y: 0, width: 100, height: 50), source: CGRect(x: 90, y: 40, width: 50, height: 20)))
        let link = LensNotes.connector(note: CGRect(x: 400, y: 100, width: 200, height: 80), source: CGRect(x: 40, y: 120, width: 120, height: 24))
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.from.x ?? 0, 392, accuracy: 0.001); XCTAssertEqual(link?.to.x ?? 0, 160, accuracy: 0.001)
        let opened = LensNotes.opened(CGRect(x: 740, y: 1000, width: 260, height: 120), pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(opened, CGPoint(x: 500, y: 896))
    }

    func testIconGoesBesideTheTextOnAFreeSpot() {
        let anchor = CGRect(x: 100, y: 100, width: 200, height: 30)
        XCTAssertEqual(LensNotes.badgePlacement(near: anchor, occupied: [], pageWidth: 768, pageHeight: 1024).minX, 306)
        let left = LensNotes.badgePlacement(near: anchor, occupied: [CGRect(x: 300, y: 90, width: 200, height: 60)], pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(left.maxX, 94); XCTAssertFalse(left.intersects(anchor))
        let corner = LensNotes.badgePlacement(near: nil, occupied: [], pageWidth: 768, pageHeight: 1024)
        XCTAssertEqual(corner, CGRect(x: 726, y: 24, width: 30, height: 30))
    }

    func testPlacementSaysWhenTheNoteWouldCoverSomething() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 20)
        XCTAssertTrue(LensGeometry.placementResult(text: "Breve", near: anchor, occupied: [], pageWidth: 768, pageHeight: 1024).clear)
        let full = [CGRect(x: 0, y: 0, width: 768, height: 1024)]
        let covered = LensGeometry.placementResult(text: "Breve", near: anchor, occupied: full, pageWidth: 768, pageHeight: 1024)
        XCTAssertFalse(covered.clear); XCTAssertFalse(covered.rect.intersects(anchor))
        XCTAssertEqual(LensGeometry.placement(text: "Breve", near: anchor, occupied: [], pageWidth: 768, pageHeight: 1024),
                       LensGeometry.placementResult(text: "Breve", near: anchor, occupied: [], pageWidth: 768, pageHeight: 1024).rect)
    }

    func testValidationRejectsDamagedNoteData() {
        var page = PageSnapshot()
        page.texts = [note("Valida", body: "Ok", at: .zero, source: LensNoteSource(pageID: page.id, rect: CGRect(x: 1, y: 2, width: 3, height: 4)))]
        XCTAssertNoThrow(try PageValidation.validate(page))
        page.texts[0].lensNote?.source?.x = .nan
        XCTAssertThrowsError(try PageValidation.validate(page))
        page.texts[0].lensNote?.source = nil; page.texts[0].lensNote?.title = String(repeating: "a", count: 401)
        XCTAssertThrowsError(try PageValidation.validate(page))
    }

    func testCopiedNotebookPointsNotesAtItsOwnPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), document = UUID(), book = UUID()
        try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        var origin = try await workspace.addPage(); let other = try await workspace.addPage()
        origin.texts = [note("Qui", body: "Sulla stessa pagina", at: CGPoint(x: 300, y: 40), source: LensNoteSource(pageID: origin.id, rect: CGRect(x: 20, y: 40, width: 80, height: 20))),
                        note("Altrove", body: "Testo su un’altra pagina", at: CGPoint(x: 300, y: 200), source: LensNoteSource(pageID: other.id, rect: CGRect(x: 5, y: 5, width: 50, height: 20)))]
        origin.revision += 1; _ = try await workspace.save(origin, drawing: Data([5]))
        let copyID = UUID(), copyBook = UUID(); try await workspace.clone(to: store, documentID: copyID, notebookID: copyBook)
        let copy = DocumentWorkspace(package: store.packageURL(for: copyID), documentID: copyID, notebookID: copyBook)
        let pages = try await copy.pages()
        XCTAssertEqual(pages[0].texts[0].lensNote?.source?.pageID, pages[0].id)
        XCTAssertEqual(pages[0].texts[1].lensNote?.source?.pageID, pages[1].id)
        XCTAssertEqual(pages[0].texts[0].lensNote?.source?.rect, CGRect(x: 20, y: 40, width: 80, height: 20))
    }
}
