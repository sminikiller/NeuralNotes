import XCTest
@testable import NeuralNotesCore

final class LookupCardTests: XCTestCase {
    private let reference = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 4)
    private var request: LookupRequest { LookupRequest(term: "Entropia", sources: [IndexedChunk(text: "Fonte verificata", reference: reference)]) }
    func testCardMapsStructuredSectionsIntoArtifactAndValidatesSources() throws {
        let card = LookupCard(term: "Entropia", definition: "Definizione [1]", explanation: "Spiegazione", examples: ["Esempio [1]"], relatedTerms: ["Calore"], references: [reference], provider: "fixture")
        XCTAssertEqual(try card.validated(for: request).definition, "Definizione [1]")
        XCTAssertEqual(card.artifact.references, [reference]); XCTAssertTrue(card.artifact.text.contains("• Esempio [1]"))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LookupCard.self, from: encoder.encode(card))
        XCTAssertEqual(try decoded.validated(for: request).id, card.id)
    }
    func testCardRejectsInventedReferencesAndCitationsInEverySection() {
        var card = LookupCard(term: "Entropia", definition: "Definizione", references: [reference], provider: "fixture")
        card.explanation = "Risposta [2]"; XCTAssertThrowsError(try card.validated(for: request))
        card.explanation = ""; card.references = [SourceReference(documentID: UUID())]; XCTAssertThrowsError(try card.validated(for: request))
        card.references = [reference]; card.term = "Altra cosa"; XCTAssertThrowsError(try card.validated(for: request))
        card.term = "Entropia"; card.examples = Array(repeating: "x", count: 6); XCTAssertThrowsError(try card.validated(for: request))
    }
    func testLookupURLIsDerivedOnlyForTheExplicitBackendStudyRoute() {
        var configuration = AIEngineConfiguration(); configuration.engine = .backend
        configuration.endpoint = "https://example.test/neuralnotes/v1/study"
        XCTAssertEqual(configuration.lookupURL?.absoluteString, "https://example.test/neuralnotes/v1/lookup")
        configuration.endpoint = "https://example.test/custom"; XCTAssertNil(configuration.lookupURL)
        configuration.endpoint = "https://example.test/v1/study?key=unsafe"; XCTAssertNil(configuration.lookupURL)
        configuration.engine = .openAI; XCTAssertNil(configuration.lookupURL)
        XCTAssertFalse(LookupRequest(term: "\n", sources: request.sources).isValid)
        XCTAssertFalse(LookupRequest(term: "Entropia", sources: []).isValid)
    }
}
