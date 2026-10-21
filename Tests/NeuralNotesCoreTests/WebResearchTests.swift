import XCTest
@testable import NeuralNotesCore

final class WebResearchTests: XCTestCase {
    func testResearchCacheIdentitySeparatesTermEngineModelAndDestination() {
        let request = WebResearchRequest(term: "Entropia"); var config = AIEngineConfiguration()
        config.engine = .backend; config.endpoint = "https://example.com/v1/study"
        let key = request.cacheKey(configuration: config); XCTAssertEqual(key.count, 64)
        XCTAssertNotEqual(WebResearchRequest(term: "Energia").cacheKey(configuration: config), key)
        config.model = "altro-modello"; XCTAssertNotEqual(request.cacheKey(configuration: config), key)
        config.model = ""; config.endpoint = "https://altro.example/v1/study"; XCTAssertNotEqual(request.cacheKey(configuration: config), key)
    }
    func testRequestsAndSourcesRejectUnsafeLinksAndControlCharacters() {
        XCTAssertTrue(WebResearchRequest(term: "  Entropia  ").isValid)
        for term in ["", "due\nrighe", "tab\tqui", String(repeating: "a", count: 121)] { XCTAssertFalse(WebResearchRequest(term: term).isValid) }
        for url in ["javascript:alert(1)", "file:///private/data", "https://user:password@example.com", "data:text/html,x"] { XCTAssertFalse(WebSource(title: "Fonte", url: url).isValid) }
        XCTAssertTrue(WebSource(title: "Fonte", url: "https://example.com/fisica").isValid)
    }
    func testUnicodeCitationRunsKeepAllTextAndMakeSourceMarkersClickable() throws {
        let text = "Energia 👨‍👩‍👧‍👦 e quantità", prefix = "Energia 👨‍👩‍👧‍👦"
        let source = WebSource(title: "Lezione", url: "https://example.com/fisica", endIndex: prefix.utf16.count)
        let artifact = AIArtifact(text: text, references: [], provider: "fixture · web", webSources: [source])
        _ = try artifact.validatedWebResearch()
        let runs = artifact.citedRuns
        XCTAssertEqual(runs.first?.text, prefix); XCTAssertEqual(runs[1].text, " [1]"); XCTAssertEqual(runs[1].link, source.link)
        XCTAssertTrue(runs.map(\.text).joined().contains(" e quantità")); XCTAssertTrue(runs.last?.text.contains(source.url) == true)
        let midEmoji = AIArtifact(text: text, references: [], provider: "fixture", webSources: [WebSource(title: "Fonte", url: source.url, endIndex: 10)])
        XCTAssertTrue(midEmoji.citedRuns.map(\.text).joined().contains(text))
        let unsafe = AIArtifact(text: text, references: [], provider: "fixture", webSources: [WebSource(title: "Bad", url: "javascript:x")])
        XCTAssertThrowsError(try unsafe.validatedWebResearch()); XCTAssertTrue(unsafe.citedRuns.allSatisfy { $0.link == nil })
        XCTAssertThrowsError(try AIArtifact(text: text, references: [], provider: "fixture", webSources: []).validatedWebResearch())
    }
    func testWebSourcesSurviveArtifactAndConversationClone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let writer = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        _ = try await writer.addPage()
        let source = WebSource(title: "Fonte verificata dal test", url: "https://example.com/fonte", endIndex: 4)
        let artifact = AIArtifact(text: "Dato", references: [], provider: "fixture · web", webSources: [source])
        try await writer.saveArtifact(artifact); try await writer.saveConversationTurn(AIConversationTurn(question: "Ricerca", answer: artifact))
        let document = UUID(), book = UUID(); try store.clone(from: writer.package, documentID: document, notebookID: book)
        let clone = DocumentWorkspace(package: store.packageURL(for: document), documentID: document, notebookID: book)
        let artifacts = try await clone.artifacts(), catalog = try await clone.catalog()
        XCTAssertEqual(artifacts.first?.webSources, [source]); XCTAssertEqual(catalog.conversation?.first?.answer.webSources, [source])
    }
}
