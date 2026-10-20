import XCTest
@testable import NeuralNotesCore

final class PageLinksTests: XCTestCase {
    func testForwardAndBacklinksFollowLivePagesAndDuplicateLabelsKeepTheirIdentities() throws {
        let document = UUID(); var origin = PageSnapshot(); let destination = PageSnapshot()
        let target = PageLinkTarget(documentID: document, pageID: destination.id)
        var first = TextElement(text: "Definizione"); first.pageLink = target
        var second = first; second.id = UUID(); origin.texts = [first, second]
        let links = PageLinks.backlinks(to: target, in: [origin, destination])
        XCTAssertEqual(links.count, 2); XCTAssertEqual(Set(links.map(\.id)).count, 2)
        XCTAssertEqual(links.first?.originPageID, origin.id)
        XCTAssertTrue(PageLinks.backlinks(to: target, in: [destination]).isEmpty)
        XCTAssertTrue(PageLinks.backlinks(to: PageLinkTarget(documentID: UUID(), pageID: destination.id), in: [origin]).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(TextElement.self, from: JSONEncoder().encode(first)).pageLink, target)
    }
    func testCloneAndMergeResolveForwardLinksAndLeaveExternalSourcesIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), document = UUID(), book = UUID(), foreign = UUID()
        try store.create(DocumentManifest(documentID: document, notebookID: book))
        let workspace = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        var origin = try await workspace.addPage(); let destination = try await workspace.addPage()
        var local = TextElement(text: "Fonte locale"); local.pageLink = PageLinkTarget(documentID: document, pageID: destination.id)
        var external = TextElement(text: "Altra fonte"); external.pageLink = PageLinkTarget(documentID: foreign, pageID: UUID())
        origin.texts = [local, external]; origin.revision += 1; _ = try await workspace.save(origin, drawing: Data([5]))
        let copyID = UUID(), copyBook = UUID(); try await workspace.clone(to: store, documentID: copyID, notebookID: copyBook)
        let copy = DocumentWorkspace(package: store.packageURL(for: copyID), documentID: copyID, notebookID: copyBook)
        let pages = try await copy.pages()
        XCTAssertEqual(pages[0].texts[0].pageLink, PageLinkTarget(documentID: copyID, pageID: pages[1].id))
        XCTAssertEqual(pages[0].texts[1].pageLink, external.pageLink)
        let merged = try await workspace.appendNative(from: copy.package)
        XCTAssertEqual(merged[0].texts[0].pageLink, PageLinkTarget(documentID: document, pageID: merged[1].id))
        XCTAssertEqual(merged[0].texts[1].pageLink, external.pageLink)
        let original = try await workspace.pageSnapshot(origin.id); XCTAssertEqual(original.texts[0].pageLink, local.pageLink)
        _ = try NativePackageInspector.inspect(workspace.package)
    }
}
