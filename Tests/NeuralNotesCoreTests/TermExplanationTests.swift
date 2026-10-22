import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NeuralNotesCore

final class TermExplanationTests: XCTestCase {
    private func config(_ engine: AIEngine) -> AIEngineConfiguration {
        var value = AIEngineConfiguration(); value.engine = engine; value.model = "model-test"; return value
    }
    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
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

    func testQuestionsPassagesAndImagesAreValidButNeverAutomaticNotes() {
        let asked = TermExplanationRequest(term: "", selection: "La mitosi divide il nucleo.\nSegue la citocinesi.", question: " Riassumi in tre punti ")
        XCTAssertTrue(asked.isValid); XCTAssertFalse(asked.isTerm); XCTAssertEqual(asked.question, "Riassumi in tre punti"); XCTAssertEqual(asked.title, "Riassumi in tre punti")
        let photo = TermExplanationRequest(term: "", question: "", image: "aGVsbG8=")
        XCTAssertTrue(photo.isValid); XCTAssertFalse(photo.isTerm); XCTAssertEqual(photo.title, "Immagine")
        XCTAssertFalse(TermExplanationRequest(term: "", image: "not base64!").isValid)
        XCTAssertFalse(TermExplanationRequest(term: "", image: String(repeating: "A", count: 1_400_001)).isValid)
        XCTAssertNil(TermExplanationRequest(term: "x", image: "").image)
        XCTAssertEqual(TermExplanationRequest(term: "", selection: "Brano\nsu due righe").title, "Brano su due righe")
    }

    func testEveryPersonalEngineSendsTermContextAndSubjectWithoutNotebookIdentity() throws {
        let input = TermExplanationRequest(term: "mitocondrio", context: "La cellula produce energia nel mitocondrio.", subject: "Biologia")
        for engine in [AIEngine.openAI, .anthropic, .gemini, .deepSeek] {
            let call = try DirectAIWire.explainRequest(input, configuration: config(engine), credential: "key")
            let body = String(decoding: try XCTUnwrap(call.httpBody), as: UTF8.self)
            XCTAssertTrue(body.contains("mitocondrio")); XCTAssertTrue(body.contains("Biologia")); XCTAssertTrue(body.contains("conoscenza generale"))
            XCTAssertFalse(body.contains("image")); if engine == .openAI { XCTAssertTrue(body.contains("neuralnotes_explain")) }
        }
        XCTAssertThrowsError(try DirectAIWire.explainRequest(input, configuration: config(.backend), credential: "key"))
    }

    func testImagesTravelInTheFormatOfEachProvider() throws {
        let input = TermExplanationRequest(term: "", question: "Chi è la persona nella foto?", image: "aGVsbG8=")
        let openAI = try json(DirectAIWire.explainRequest(input, configuration: config(.openAI), credential: "key"))
        let message = try XCTUnwrap((openAI["input"] as? [[String: Any]])?.first)
        let parts = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["type"] as? String }, ["input_text", "input_image"])
        XCTAssertEqual(parts.last?["image_url"] as? String, "data:image/jpeg;base64,aGVsbG8=")
        XCTAssertTrue((parts.first?["text"] as? String)?.contains("Chi è la persona") == true)
        let claude = try json(DirectAIWire.explainRequest(input, configuration: config(.anthropic), credential: "key"))
        let blocks = try XCTUnwrap(((claude["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(blocks.first?["type"] as? String, "image")
        XCTAssertEqual((blocks.first?["source"] as? [String: Any])?["data"] as? String, "aGVsbG8=")
        let gemini = try json(DirectAIWire.explainRequest(input, configuration: config(.gemini), credential: "key"))
        let geminiParts = try XCTUnwrap(((gemini["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        XCTAssertEqual((geminiParts.first?["inline_data"] as? [String: Any])?["mime_type"] as? String, "image/jpeg"); XCTAssertNotNil(geminiParts.last?["text"])
        let deepSeek = try json(DirectAIWire.explainRequest(input, configuration: config(.deepSeek), credential: "key"))
        let user = try XCTUnwrap((deepSeek["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]])
        XCTAssertEqual(user.map { $0["type"] as? String }, ["text", "image_url"])
        XCTAssertEqual((user.last?["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,aGVsbG8=")
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
        XCTAssertEqual(try TermExplanation(term: "x", kind: "immagine", explanation: String(repeating: "a", count: 4000), certain: true, provider: "p").validated(for: input).kind, "immagine")
        XCTAssertThrowsError(try TermExplanation(term: "x", kind: "data", explanation: "  ", certain: true, provider: "p").validated(for: input))
        XCTAssertThrowsError(try TermExplanation(term: "x", kind: "data", explanation: String(repeating: "a", count: 4001), certain: true, provider: "p").validated(for: input))
        var backend = AIEngineConfiguration(); backend.engine = .backend; backend.endpoint = "https://gateway.example/v1/study"
        XCTAssertEqual(backend.explainURL?.absoluteString, "https://gateway.example/v1/explain")
    }

    func testWobblyHandDrawnLinesCountAsUnderlinesButCirclesDoNot() {
        XCTAssertTrue(LensGeometry.isUnderline(width: 100, height: 2)); XCTAssertTrue(LensGeometry.isUnderline(width: 120, height: 18))
        XCTAssertFalse(LensGeometry.isUnderline(width: 60, height: 20)); XCTAssertFalse(LensGeometry.isUnderline(width: 100, height: 100))
        XCTAssertFalse(LensGeometry.isUnderline(width: .nan, height: 1))
        let wobbly = [StrokeSample(x: 10, y: 200), StrokeSample(x: 60, y: 212), StrokeSample(x: 130, y: 196)]
        XCTAssertTrue(LensGeometry.isUnderline(trace: wobbly))
        let area = LensGeometry.selection(trace: wobbly, pageWidth: 768, pageHeight: 1024)
        XCTAssertNotNil(area); XCTAssertLessThan(area?.minY ?? 999, 196); XCTAssertTrue(area?.contains(CGPoint(x: 70, y: 180)) ?? false)
        XCTAssertFalse(LensGeometry.isUnderline(trace: [StrokeSample(x: 0, y: 0), StrokeSample(x: 50, y: 50), StrokeSample(x: 0, y: 50)]))
        XCTAssertFalse(LensGeometry.isUnderline(trace: []))
    }
}
