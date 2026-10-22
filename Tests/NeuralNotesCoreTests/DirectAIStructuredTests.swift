import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NeuralNotesCore

final class DirectAIStructuredTests: XCTestCase {
    private let first = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 2)
    private let second = SourceReference(documentID: UUID(), audioSessionID: UUID(), seconds: 95)
    private var sources: [IndexedChunk] { [IndexedChunk(text: "Entropia: misura del disordine", reference: first), IndexedChunk(text: "Calore e temperatura", reference: second)] }
    private func config(_ engine: AIEngine) -> AIEngineConfiguration {
        var value = AIEngineConfiguration(); value.engine = engine; value.model = "model-test"
        if engine == .compatibleResponses { value.endpoint = "https://host.example/v1/responses" }
        return value
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    /// The provider envelope around a JSON answer, for every personal engine.
    private func envelope(_ engine: AIEngine, _ payload: [String: Any]) throws -> Data {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let root: [String: Any]
        switch engine {
        case .anthropic: root = ["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]]]
        case .gemini: root = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": text]]]]]]
        case .deepSeek: root = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": text]]]]
        default: root = ["status": "completed", "output": [["type": "reasoning"], ["type": "message", "status": "completed", "content": [["type": "output_text", "text": text]]]]]
        }
        return try JSONSerialization.data(withJSONObject: root)
    }
    private let engines: [AIEngine] = [.openAI, .anthropic, .gemini, .deepSeek, .compatibleResponses]

    func testDeepSeekIsAPersonalEngineWithItsOwnDestinationAndConsent() throws {
        let value = config(.deepSeek)
        XCTAssertEqual(value.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(value.destination, "api.deepseek.com"); XCTAssertNotEqual(value.consentKey, config(.openAI).consentKey)
        let call = try DirectAIWire.request(AIRequest(task: .chat, question: "Spiega", sources: sources), configuration: value, credential: "secret-fixture")
        XCTAssertEqual(call.value(forHTTPHeaderField: "Authorization"), "Bearer secret-fixture")
        let json = try body(call)
        XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("JSON") == true)
        XCTAssertFalse(String(decoding: call.httpBody!, as: UTF8.self).contains("secret-fixture"))
        XCTAssertFalse(String(decoding: call.httpBody!, as: UTF8.self).contains(first.documentID.uuidString))
    }

    func testStructuredRequestsUseTaskSchemasAndSendOnlySourceText() throws {
        let lookup = LookupRequest(term: "Entropia", sources: sources), quiz = QuizRequest(sources: sources, count: 3), cards = FlashcardRequest(sources: sources, count: 4, focus: "calore")
        for engine in engines {
            let calls = [try DirectAIWire.lookupRequest(lookup, configuration: config(engine), credential: "key"),
                         try DirectAIWire.quizRequest(quiz, configuration: config(engine), credential: "key"),
                         try DirectAIWire.flashcardsRequest(cards, configuration: config(engine), credential: "key")]
            for (call, name) in zip(calls, ["neuralnotes_lookup", "neuralnotes_quiz", "neuralnotes_cards"]) {
                let text = String(decoding: try XCTUnwrap(call.httpBody), as: UTF8.self), json = try body(call)
                XCTAssertFalse(text.contains(first.documentID.uuidString), "\(engine) \(name) leaked a source identity")
                switch engine {
                case .openAI, .compatibleResponses:
                    let format = try XCTUnwrap((json["text"] as? [String: Any])?["format"] as? [String: Any])
                    XCTAssertEqual(format["name"] as? String, name); XCTAssertEqual(format["strict"] as? Bool, true); XCTAssertEqual(json["store"] as? Bool, false)
                case .anthropic:
                    let format = try XCTUnwrap((json["output_config"] as? [String: Any])?["format"] as? [String: Any])
                    XCTAssertEqual(format["type"] as? String, "json_schema"); XCTAssertNotNil(format["schema"])
                case .gemini: XCTAssertNotNil((json["generationConfig"] as? [String: Any])?["responseJsonSchema"])
                default: XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
                }
            }
        }
        let user = try XCTUnwrap(try body(DirectAIWire.flashcardsRequest(cards, configuration: config(.openAI), credential: "key"))["input"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any])
        XCTAssertEqual(payload["focus"] as? String, "calore"); XCTAssertEqual(payload["count"] as? Int, 4)
        XCTAssertThrowsError(try DirectAIWire.lookupRequest(LookupRequest(term: "a\nb", sources: sources), configuration: config(.openAI), credential: "key"))
        XCTAssertThrowsError(try DirectAIWire.quizRequest(quiz, configuration: config(.backend), credential: "key"))
    }

    func testLookupQuizAndCardsParseEveryProviderWithSequentialCitations() throws {
        let lookup = LookupRequest(term: "Entropia", sources: sources)
        let lookupPayload: [String: Any] = ["term": "entropia", "definition": "Misura del disordine [2]", "explanation": "Legata al calore [2] e alla temperatura [1].",
                                            "examples": ["Ghiaccio che fonde [2]"], "relatedTerms": ["Calore"], "citations": [2, 1]]
        let quiz = QuizRequest(sources: sources, count: 2)
        let quizPayload: [String: Any] = ["title": "Termodinamica", "questions": [["prompt": "Che cosa misura l’entropia? [2]", "options": ["Il disordine [2]", "La massa", "La carica", "Il volume"],
                                                                                  "correctIndex": 0, "explanation": "Dalle fonti [2]", "citations": [2]]]]
        let cards = FlashcardRequest(sources: sources, count: 3)
        let cardsPayload: [String: Any] = ["cards": [["question": "Che cos’è l’entropia? [1]", "answer": "Una misura del disordine [1]", "citations": [1]],
                                                     ["question": "che cos’è l’entropia? [1] ", "answer": "Duplicato [1]", "citations": [1]],
                                                     ["question": "Che legame c’è con il calore?", "answer": "Il calore la fa crescere [2]", "citations": [2]]]]
        for engine in engines {
            let card = try DirectAIWire.lookupCard(envelope(engine, lookupPayload), request: lookup, configuration: config(engine))
            XCTAssertEqual(card.term, "Entropia"); XCTAssertEqual(card.definition, "Misura del disordine [1]")
            XCTAssertEqual(card.explanation, "Legata al calore [1] e alla temperatura [2]."); XCTAssertEqual(card.references, [second, first])
            XCTAssertEqual(card.provider, "\(engine.title) / model-test")
            let bank = try DirectAIWire.quizBank(envelope(engine, quizPayload), request: quiz, configuration: config(engine))
            XCTAssertEqual(bank.questions.first?.prompt, "Che cosa misura l’entropia? [1]"); XCTAssertEqual(bank.questions.first?.references, [second])
            XCTAssertEqual(bank.questions.first?.options.first, "Il disordine [1]"); XCTAssertEqual(bank.title, "Termodinamica")
            let set = try DirectAIWire.flashcardSet(envelope(engine, cardsPayload), request: cards, configuration: config(engine))
            XCTAssertEqual(set.cards.count, 2, "duplicate question must be dropped for \(engine)")
            XCTAssertEqual(set.cards[1].references, [second]); XCTAssertEqual(set.cards[1].answer, "Il calore la fa crescere [1]")
        }
    }

    func testStructuredResultsRejectInventedCitationsWrongTermsAndOversizedSets() throws {
        let lookup = LookupRequest(term: "Entropia", sources: sources)
        let invalidLookups: [[String: Any]] = [
            ["term": "Calore", "definition": "Altro [1]", "explanation": "", "examples": [], "relatedTerms": [], "citations": [1]],
            ["term": "Entropia", "definition": "Senza fonti", "explanation": "", "examples": [], "relatedTerms": [], "citations": []],
            ["term": "Entropia", "definition": "Fonte inventata [3]", "explanation": "", "examples": [], "relatedTerms": [], "citations": [3]],
            ["term": "Entropia", "definition": "Marcatore estraneo [2]", "explanation": "", "examples": [], "relatedTerms": [], "citations": [1]],
            ["term": "Entropia", "definition": "Troppi esempi [1]", "explanation": "", "examples": ["a", "b", "c", "d", "e", "f"], "relatedTerms": [], "citations": [1]]]
        for payload in invalidLookups {
            XCTAssertThrowsError(try DirectAIWire.lookupCard(envelope(.openAI, payload), request: lookup, configuration: config(.openAI)))
        }
        let quiz = QuizRequest(sources: sources, count: 1)
        let question: [String: Any] = ["prompt": "Domanda [1]", "options": ["A", "B", "C", "D"], "correctIndex": 0, "explanation": "Motivo [1]", "citations": [1]]
        for mutation in [["options": ["A", "B", "C"]], ["correctIndex": 4], ["options": ["A", "a", "B", "C"]], ["citations": [5]]] as [[String: Any]] {
            let changed = question.merging(mutation) { $1 }
            XCTAssertThrowsError(try DirectAIWire.quizBank(envelope(.anthropic, ["title": "Quiz", "questions": [changed]]), request: quiz, configuration: config(.anthropic)))
        }
        XCTAssertThrowsError(try DirectAIWire.quizBank(envelope(.gemini, ["title": "Quiz", "questions": [question, question]]), request: quiz, configuration: config(.gemini)))
        let cards = FlashcardRequest(sources: sources, count: 1)
        let card: [String: Any] = ["question": "Q [1]", "answer": "A [1]", "citations": [1]]
        XCTAssertThrowsError(try DirectAIWire.flashcardSet(envelope(.deepSeek, ["cards": [card, card]]), request: cards, configuration: config(.deepSeek)))
        XCTAssertThrowsError(try DirectAIWire.flashcardSet(envelope(.deepSeek, ["cards": []]), request: cards, configuration: config(.deepSeek)))
        XCTAssertThrowsError(try DirectAIWire.flashcardSet(envelope(.deepSeek, ["cards": [["question": "Q", "answer": "", "citations": [1]]]]), request: cards, configuration: config(.deepSeek)))
        // A title that is not a valid library name falls back instead of losing a valid quiz.
        let titled = try DirectAIWire.quizBank(envelope(.openAI, ["title": "Riga\nspezzata", "questions": [question]]), request: quiz, configuration: config(.openAI))
        XCTAssertEqual(titled.title, "Quiz dalle fonti")
    }

    func testProviderEnvelopesRejectTruncationRefusalAndToolBlocks() throws {
        let request = AIRequest(task: .chat, question: "Spiega", sources: sources)
        let answer = "{\"text\":\"Risposta [1]\",\"citations\":[1]}"
        let thinking: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": answer]]]
        XCTAssertEqual(try DirectAIWire.artifact(JSONSerialization.data(withJSONObject: thinking), request: request, engine: .anthropic).text, "Risposta [1]")
        let invalid: [(AIEngine, [String: Any])] = [
            (.anthropic, ["stop_reason": "max_tokens", "content": [["type": "text", "text": answer]]]),
            (.anthropic, ["stop_reason": "refusal", "content": []]),
            (.anthropic, ["stop_reason": "end_turn", "content": [["type": "tool_use", "name": "x"], ["type": "text", "text": answer]]]),
            (.anthropic, ["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": ""]]]),
            (.deepSeek, ["choices": [["finish_reason": "length", "message": ["content": answer]]]]),
            (.deepSeek, ["choices": [["finish_reason": "stop", "message": ["content": answer, "refusal": "No"]]]]),
            (.deepSeek, ["choices": [["finish_reason": "stop", "message": ["content": answer]], ["finish_reason": "stop", "message": ["content": answer]]]]),
            (.deepSeek, ["choices": []])]
        for (engine, root) in invalid {
            XCTAssertThrowsError(try DirectAIWire.artifact(JSONSerialization.data(withJSONObject: root), request: request, engine: engine))
        }
        let deepSeek: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": answer, "refusal": NSNull()]]]]
        XCTAssertEqual(try DirectAIWire.artifact(JSONSerialization.data(withJSONObject: deepSeek), request: request, engine: .deepSeek).references, [first])
    }

    func testPersonalWebResearchSendsOnlyTheTermAndKeepsAnnotatedSources() throws {
        let input = WebResearchRequest(term: "Teorema di Pitagora")
        let call = try DirectAIWire.researchRequest(input, configuration: config(.openAI), credential: "key")
        let json = try body(call)
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search"); XCTAssertEqual(json["max_tool_calls"] as? Int, 1)
        XCTAssertEqual(json["store"] as? Bool, false); XCTAssertEqual(json["input"] as? String, "{\"term\":\"Teorema di Pitagora\"}")
        for engine in [AIEngine.anthropic, .gemini, .deepSeek, .backend, .offline] {
            XCTAssertThrowsError(try DirectAIWire.researchRequest(input, configuration: config(engine), credential: "key"))
        }
        func response(_ annotations: [[String: Any]], searched: Bool = true, text: String = "In un triangolo rettangolo.") throws -> Data {
            var output: [[String: Any]] = [["type": "message", "status": "completed", "content": [["type": "output_text", "text": text, "annotations": annotations]]]]
            if searched { output.insert(["type": "web_search_call", "status": "completed"], at: 0) }
            return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": output])
        }
        let valid: [String: Any] = ["type": "url_citation", "title": "Enciclopedia", "url": "https://example.com/pitagora", "end_index": 10]
        let artifact = try DirectAIWire.research(response([valid]), configuration: config(.openAI))
        XCTAssertEqual(artifact.webSources?.first?.url, "https://example.com/pitagora"); XCTAssertEqual(artifact.webSources?.first?.endIndex, 10)
        XCTAssertTrue(artifact.references.isEmpty); XCTAssertTrue(artifact.provider.hasSuffix("· web"))
        XCTAssertThrowsError(try DirectAIWire.research(response([valid], searched: false), configuration: config(.openAI)))
        XCTAssertThrowsError(try DirectAIWire.research(response([]), configuration: config(.openAI)))
        XCTAssertThrowsError(try DirectAIWire.research(response([valid.merging(["url": "javascript:alert(1)"]) { $1 }]), configuration: config(.openAI)))
        XCTAssertThrowsError(try DirectAIWire.research(response([valid.merging(["end_index": 999]) { $1 }]), configuration: config(.openAI)))
    }

    func testFlashcardDraftsBecomeCardsOnlyWithASourceAndConfigurationAdvertisesTools() throws {
        let draft = FlashcardDraft(question: "  Che cos’è l’entropia? ", answer: "Una misura del disordine. ", references: [first])
        let card = try XCTUnwrap(draft.card(now: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(card.question, "Che cos’è l’entropia?"); XCTAssertEqual(card.source, first); XCTAssertEqual(card.dueAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(FlashcardDraft(question: "Q", answer: "A", references: []).card())
        XCTAssertFalse(FlashcardRequest(sources: sources, count: 21).isValid); XCTAssertFalse(FlashcardRequest(sources: [], count: 3).isValid)
        XCTAssertFalse(FlashcardRequest(sources: sources, count: 3, focus: String(repeating: "x", count: 301)).isValid)
        var backend = AIEngineConfiguration(); backend.engine = .backend; backend.endpoint = "https://gateway.example/v1/study"
        XCTAssertEqual(backend.cardsURL?.absoluteString, "https://gateway.example/v1/cards")
        XCTAssertTrue(backend.supportsStructuredStudy); XCTAssertTrue(backend.supportsWebResearch)
        backend.endpoint = "https://gateway.example/other"; XCTAssertFalse(backend.supportsStructuredStudy); XCTAssertNil(backend.cardsURL)
        XCTAssertTrue(config(.deepSeek).supportsStructuredStudy); XCTAssertFalse(config(.deepSeek).supportsWebResearch)
        XCTAssertTrue(config(.openAI).supportsWebResearch); XCTAssertFalse(config(.anthropic).supportsWebResearch)
        XCTAssertFalse(AIEngineConfiguration().supportsStructuredStudy)
    }
}

final class LocalFlashcardTests: XCTestCase {
    func testLocalLensCardAsksAboutTheSubjectAndKeepsTwoSentences() {
        let reference = SourceReference(documentID: UUID())
        let card = FlashcardDraft.local(subject: "  Entropia:\nseconda riga", answer: "È una misura del disordine [1]. Cresce nei sistemi isolati. Terza frase.", reference: reference)
        XCTAssertEqual(card.question, "Che cosa sai di «Entropia»?")
        XCTAssertEqual(card.answer, "È una misura del disordine [1]. Cresce nei sistemi isolati.")
        XCTAssertEqual(card.references, [reference]); XCTAssertTrue(card.isValid)
        let long = FlashcardDraft.local(subject: String(repeating: "a", count: 200), answer: "Senza punto finale", reference: reference)
        XCTAssertTrue(long.question.hasSuffix("…»?")); XCTAssertEqual(long.answer, "Senza punto finale")
        XCTAssertEqual(FlashcardDraft.local(subject: "  ", answer: "Testo.", reference: reference).question, "Che cosa dicono le fonti?")
    }
}
