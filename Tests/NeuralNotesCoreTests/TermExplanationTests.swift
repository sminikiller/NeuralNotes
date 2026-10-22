import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NeuralNotesCore

final class TermExplanationTests: XCTestCase {
    private func config(_ engine: AIEngine) -> AIEngineConfiguration {
        var value = AIEngineConfiguration(); value.engine = engine; value.model = "model-test"; return value
    }

    func testRequestKeepsOneLineTermAndContextAroundIt() {
        let request = TermExplanationRequest(term: "  Congresso\n di Vienna ", context: "x", subject: "Storia\ncontemporanea")
        XCTAssertEqual(request.term, "Congresso di Vienna"); XCTAssertEqual(request.subject, "Storia contemporanea"); XCTAssertTrue(request.isTerm)
        let page = String(repeating: "a ", count: 1000) + "Dopo il congresso di Vienna l’Europa cambiò." + String(repeating: " b", count: 1000)
        let context = TermExplanationRequest.context(for: "Congresso di Vienna", in: page, radius: 20)
        XCTAssertTrue(context.contains("congresso di Vienna")); XCTAssertLessThanOrEqual(context.count, 19 + 40 + 1)
        XCTAssertEqual(TermExplanationRequest.context(for: "assente", in: "Testo breve della pagina"), "Testo breve della pagina")
        XCTAssertEqual(TermExplanationRequest.context(for: "x", in: "  \n "), "")
        XCTAssertFalse(TermExplanationRequest(term: String(repeating: "parola ", count: 20)).isTerm)
        XCTAssertFalse(TermExplanationRequest(term: " \n ").isValid)
    }

    func testEveryPersonalEngineSendsTermContextAndSubjectWithoutNotebookIdentity() throws {
        let input = TermExplanationRequest(term: "mitocondrio", context: "La cellula produce energia nel mitocondrio.", subject: "Biologia")
        for engine in [AIEngine.openAI, .anthropic, .gemini, .deepSeek] {
            let call = try DirectAIWire.explainRequest(input, configuration: config(engine), credential: "key")
            let body = String(decoding: try XCTUnwrap(call.httpBody), as: UTF8.self)
            XCTAssertTrue(body.contains("mitocondrio")); XCTAssertTrue(body.contains("Biologia")); XCTAssertTrue(body.contains("conoscenza generale"))
            if engine == .openAI { XCTAssertTrue(body.contains("neuralnotes_explain")) }
        }
        XCTAssertThrowsError(try DirectAIWire.explainRequest(input, configuration: config(.backend), credential: "key"))
    }

    func testParsesExplanationKeepsUnderlinedTermAndFlagsUncertainty() throws {
        let input = TermExplanationRequest(term: "Napoleone", context: "Le campagne di Napoleone", subject: "Storia")
        let payload: [String: Any] = ["term": "Napoleone Bonaparte", "kind": "Persona", "explanation": "  Generale e imperatore dei francesi (1769–1821).  ", "certain": false]
        let envelope: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)]]]]
        let value = try DirectAIWire.termExplanation(JSONSerialization.data(withJSONObject: envelope), request: input, configuration: config(.deepSeek))
        XCTAssertEqual(value.term, "Napoleone"); XCTAssertEqual(value.kind, "persona"); XCTAssertEqual(value.explanation, "Generale e imperatore dei francesi (1769–1821).")
        XCTAssertEqual(value.noteBody, "Generale e imperatore dei francesi (1769–1821). (da verificare)"); XCTAssertEqual(value.provider, "DeepSeek API / model-test")
        XCTAssertTrue(value.origin.contains("non dalle tue fonti"))
        let other = try TermExplanation(term: "x", kind: "pianeta", explanation: "Testo", certain: true, provider: "p").validated(for: input)
        XCTAssertEqual(other.kind, "altro"); XCTAssertEqual(other.noteBody, "Testo")
        XCTAssertThrowsError(try TermExplanation(term: "x", kind: "data", explanation: "  ", certain: true, provider: "p").validated(for: input))
        XCTAssertThrowsError(try TermExplanation(term: "x", kind: "data", explanation: String(repeating: "a", count: 1201), certain: true, provider: "p").validated(for: input))
        var backend = AIEngineConfiguration(); backend.engine = .backend; backend.endpoint = "https://gateway.example/v1/study"
        XCTAssertEqual(backend.explainURL?.absoluteString, "https://gateway.example/v1/explain")
    }
}
