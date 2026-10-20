import XCTest
@testable import NeuralNotesCore

final class AIEngineTests: XCTestCase {
    private let input = AIRequest(task: .chat, question: "Spiega", sources: [IndexedChunk(text: "Fonte: massa e accelerazione", reference: SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 3))])
    private func config(_ engine: AIEngine) -> AIEngineConfiguration {
        var value = AIEngineConfiguration(); value.engine = engine; value.model = "model-test"; return value
    }
    func testProviderCredentialsNeverCrossHeadersOrHosts() throws {
        for engine in [AIEngine.openAI, .anthropic, .gemini] {
            let request = try DirectAIWire.request(input, configuration: config(engine), credential: "secret-fixture")
            XCTAssertEqual(request.url?.host, config(engine).destination)
            XCTAssertFalse(request.url!.absoluteString.contains("secret"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), engine == .openAI ? "Bearer secret-fixture" : nil)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), engine == .anthropic ? "secret-fixture" : nil)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), engine == .gemini ? "secret-fixture" : nil)
            XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("secret-fixture"))
        }
    }
    func testConfigurationRequiresExplicitModelAndSecureDestination() throws {
        var value = config(.compatibleResponses)
        for endpoint in ["http://host/v1", "https://user:pass@host/v1", "https://host/v1?key=secret", "https://host/v1#secret"] {
            value.endpoint = endpoint; XCTAssertNil(value.url)
        }
        value.endpoint = "https://host/v1/responses"; XCTAssertNotNil(value.url)
        value.model = ""; XCTAssertThrowsError(try DirectAIWire.request(input, configuration: value, credential: "key"))
        XCTAssertThrowsError(try DirectAIWire.request(input, configuration: config(.gemini), credential: "key\nInjected: header"))
        var gemini = config(.gemini); gemini.model = "../other?key=x"; XCTAssertNil(gemini.url)
    }
    func testPayloadTreatsSourcesAsDataAndDisablesOpenAIStorage() throws {
        let call = try DirectAIWire.request(input, configuration: config(.openAI), credential: "key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.httpBody!) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        let user = try XCTUnwrap((body["input"] as? String)?.data(using: .utf8))
        let structured = try XCTUnwrap(JSONSerialization.jsonObject(with: user) as? [String: Any])
        XCTAssertEqual(structured["question"] as? String, input.question)
        XCTAssertEqual((structured["sources"] as? [[String: Any]])?.first?["index"] as? Int, 1)
    }
    func testAllProvidersMapOnlyReturnedCitationIndices() throws {
        let answer = "{\"text\":\"Risposta\",\"citations\":[1]}"
        let envelopes: [(AIEngine, [String: Any])] = [
            (.openAI, ["status": "completed", "output": [["type": "message", "status": "completed", "content": [["type": "output_text", "text": answer]]]]]),
            (.anthropic, ["stop_reason": "end_turn", "content": [["type": "text", "text": answer]]]),
            (.gemini, ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": answer]]]]]])]
        for (engine, envelope) in envelopes {
            let artifact = try DirectAIWire.artifact(JSONSerialization.data(withJSONObject: envelope), request: input, engine: engine)
            XCTAssertEqual(artifact.text, "Risposta"); XCTAssertEqual(artifact.references, input.sources.map(\.reference))
        }
    }
    func testRejectsRefusalTruncationAndInventedCitation() throws {
        for (status, type, text) in [("incomplete", "output_text", "{}"), ("completed", "refusal", "{}"), ("completed", "output_text", "{\"text\":\"x\",\"citations\":[2]}"), ("completed", "output_text", "{\"text\":\"x\",\"citations\":[1.5]}")] {
            let body: [String: Any] = ["status": status, "output": [["type": "message", "status": "completed", "content": [["type": type, "text": text]]]]]
            XCTAssertThrowsError(try DirectAIWire.artifact(JSONSerialization.data(withJSONObject: body), request: input, engine: .openAI))
        }
        XCTAssertThrowsError(try DirectAIWire.artifact(Data(repeating: 32, count: DirectAIWire.maximumResponseBytes + 1), request: input, engine: .gemini))
        let empty = AIRequest(task: .chat, question: "x", sources: [])
        XCTAssertThrowsError(try DirectAIWire.artifact(Data("{}".utf8), request: empty, engine: .openAI))
    }
    func testChangedDestinationModelAndEngineInvalidateConsent() {
        var value = config(.openAI); let key = value.consentKey
        value.model = "another"; XCTAssertNotEqual(key, value.consentKey)
        value = config(.compatibleResponses); value.endpoint = "https://host/a"; let customKey = value.consentKey
        value.endpoint = "https://other/a"; XCTAssertNotEqual(customKey, value.consentKey)
        value.engine = .backend; XCTAssertNotEqual(customKey, value.consentKey)
    }
}
