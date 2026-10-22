import Foundation
import Security
import CryptoKit
import NeuralNotesCore

enum EngineCredentials {
    private static func query(_ engine: AIEngine) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "NeuralNotes.AIEngine", kSecAttrAccount as String: engine.rawValue]
    }
    static func load(_ engine: AIEngine) -> String {
        if engine == .backend { return BackendCredentials.load() }
        var value = query(engine); value[kSecReturnData as String] = true; value[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(value as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ credential: String, for engine: AIEngine) throws {
        if engine == .backend { try BackendCredentials.save(credential); return }
        let key = query(engine)
        if credential.isEmpty {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIWireFailure.configuration }; return
        }
        let update = [kSecValueData as String: Data(credential.utf8)]
        let status = SecItemUpdate(key as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AIWireFailure.configuration }
        var insert = key
        insert[kSecValueData as String] = Data(credential.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AIWireFailure.configuration }
    }
}

@MainActor
enum AIEngineStore {
    static func load() -> AIEngineConfiguration {
        if let data = UserDefaults.standard.data(forKey: "ai.engine.configuration"), let config = try? JSONDecoder().decode(AIEngineConfiguration.self, from: data) { return config }
        var config = AIEngineConfiguration()
        config.endpoint = UserDefaults.standard.string(forKey: "ai.backendURL") ?? ""
        if UserDefaults.standard.bool(forKey: "ai.lens.remote") { config.engine = .backend }
        return config
    }
    static func save(_ config: AIEngineConfiguration) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: "ai.engine.configuration")
    }
}

struct DirectAIProvider: AIProvider {
    let configuration: AIEngineConfiguration
    let credential: String
    func generate(_ input: AIRequest) async throws -> AIArtifact {
        let data = try await send(try DirectAIWire.request(input, configuration: configuration, credential: credential))
        return try DirectAIWire.artifact(data, request: input, engine: configuration.engine)
    }
    /// One bounded, cookie-free and redirect-free exchange with the provider.
    func send(_ call: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: call)
        guard let http = response as? HTTPURLResponse else { throw AIWireFailure.response }
        guard http.statusCode == 200 else {
            let message = http.statusCode == 429 ? "Limite del motore raggiunto. Riprova più tardi." : "Richiesta rifiutata (HTTP \(http.statusCode)). Controlla credenziale, modello e supporto JSON del motore."
            throw AIConnectionFailure.backend(message)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < DirectAIWire.maximumResponseBytes else { throw AIWireFailure.response }; data.append(byte)
        }
        return data
    }
}

@MainActor
enum AIEngineRouter {
    private static func authorization(_ configuration: AIEngineConfiguration) async throws -> (token: String, scope: String) {
        if await ManagedAIAccount.isManaged(configuration), let url = configuration.url {
            let account = try await ManagedAIAccount.client.authorization(for: url)
            return (account.token, "managed|\(url.absoluteString)|\(account.userID.uuidString)")
        }
        let token = EngineCredentials.load(configuration.engine)
        guard !token.isEmpty else { throw AIWireFailure.configuration }
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        return (token, "personal|\(configuration.consentKey)|\(hash)")
    }
    static func cacheScope(_ configuration: AIEngineConfiguration) async throws -> String {
        if configuration.engine == .offline { return "offline" }
        return try await authorization(configuration).scope
    }
    static func restoredConsent(_ configuration: AIEngineConfiguration) async -> String? {
        guard await ManagedAIAccount.isManaged(configuration), let scope = try? await cacheScope(configuration) else { return nil }
        let saved = UserDefaults.standard.string(forKey: "ai.managed.consent.\(scope)")
        return saved == configuration.consentKey ? saved : nil
    }
    static func rememberConsent(_ configuration: AIEngineConfiguration, allowed: Bool) async throws {
        guard await ManagedAIAccount.isManaged(configuration) else { return }
        let scope = try await cacheScope(configuration), key = "ai.managed.consent.\(scope)"
        if allowed { UserDefaults.standard.set(configuration.consentKey, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func research(_ input: WebResearchRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> AIArtifact {
        guard input.isValid else { throw AIWireFailure.configuration }
        if configuration.engine != .backend {
            let data = try await personal(configuration, consentKey: consentKey) { try DirectAIWire.researchRequest(input, configuration: configuration, credential: $0) }
            return try DirectAIWire.research(data, configuration: configuration)
        }
        guard let url = configuration.researchURL else { throw AIWireFailure.configuration }
        let value: AIArtifact = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validatedWebResearch()
    }
    static func quiz(_ input: QuizRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> QuizBank {
        guard input.isValid else { throw AIWireFailure.configuration }
        if configuration.engine != .backend {
            let data = try await personal(configuration, consentKey: consentKey) { try DirectAIWire.quizRequest(input, configuration: configuration, credential: $0) }
            return try DirectAIWire.quizBank(data, request: input, configuration: configuration)
        }
        guard let url = configuration.quizURL else { throw AIWireFailure.configuration }
        let value: QuizBank = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validated(for: input)
    }
    /// General-knowledge explanation of an underlined term, for the "Spiega e annota" note.
    static func explain(_ input: TermExplanationRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> TermExplanation {
        guard input.isValid, consentKey == configuration.consentKey else { throw AIWireFailure.configuration }
        if configuration.engine != .backend {
            let data = try await personal(configuration, consentKey: consentKey) { try DirectAIWire.explainRequest(input, configuration: configuration, credential: $0) }
            return try DirectAIWire.termExplanation(data, request: input, configuration: configuration)
        }
        guard let url = configuration.explainURL else { throw AIWireFailure.configuration }
        let value: TermExplanation = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validated(for: input)
    }
    static func flashcards(_ input: FlashcardRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> FlashcardSet {
        guard input.isValid else { throw AIWireFailure.configuration }
        if configuration.engine != .backend {
            let data = try await personal(configuration, consentKey: consentKey) { try DirectAIWire.flashcardsRequest(input, configuration: configuration, credential: $0) }
            return try DirectAIWire.flashcardSet(data, request: input, configuration: configuration)
        }
        guard let url = configuration.cardsURL else { throw AIWireFailure.configuration }
        let value: FlashcardSet = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validated(for: input)
    }
    /// Structured study with a personal key: same consent, credential scope and
    /// account-change check as the backend path, without leaving the device otherwise.
    private static func personal(_ configuration: AIEngineConfiguration, consentKey: String?, _ build: (String) throws -> URLRequest) async throws -> Data {
        guard configuration.engine != .offline, configuration.engine != .backend, consentKey == configuration.consentKey else { throw AIWireFailure.configuration }
        let auth = try await authorization(configuration)
        let data = try await DirectAIProvider(configuration: configuration, credential: auth.token).send(try build(auth.token))
        try Task.checkCancellation()
        guard try await cacheScope(configuration) == auth.scope else { throw CancellationError() }
        return data
    }
    private static func backendStructured<T: Decodable>(body: Data, url: URL, configuration: AIEngineConfiguration, consentKey: String?) async throws -> T {
        guard configuration.engine == .backend, consentKey == configuration.consentKey else { throw AIWireFailure.configuration }
        let auth = try await authorization(configuration), credential = auth.token
        var call = URLRequest(url: url); call.httpMethod = "POST"; call.timeoutInterval = 90
        call.setValue("application/json", forHTTPHeaderField: "Content-Type"); call.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization"); call.httpBody = body
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil); defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: call)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIConnectionFailure.backend("Richiesta non disponibile: controlla connessione, token e funzioni abilitate sul backend.") }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); guard data.count < DirectAIWire.maximumResponseBytes else { throw AIWireFailure.response }; data.append(byte) }
        try Task.checkCancellation()
        guard try await cacheScope(configuration) == auth.scope else { throw CancellationError() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(T.self, from: data)
    }
    static func lookup(_ input: LookupRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> LookupCard {
        guard input.isValid, consentKey == configuration.consentKey else { throw AIWireFailure.configuration }
        if configuration.engine != .backend {
            let data = try await personal(configuration, consentKey: consentKey) { try DirectAIWire.lookupRequest(input, configuration: configuration, credential: $0) }
            return try DirectAIWire.lookupCard(data, request: input, configuration: configuration)
        }
        guard let url = configuration.lookupURL else { throw AIWireFailure.configuration }
        let value: LookupCard = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validated(for: input)
    }
    static func generate(_ input: AIRequest, configuration: AIEngineConfiguration, consentKey: String?, onDelta: @MainActor (String) -> Void = { _ in }) async throws -> AIArtifact {
        if configuration.engine == .offline { return try await ExtractiveStudyProvider().generate(input) }
        guard consentKey == configuration.consentKey, let url = configuration.url else { throw AIWireFailure.configuration }
        let auth = try await authorization(configuration), token = auth.token
        let result: AIArtifact
        if configuration.engine == .backend {
            result = try await RemoteAIProvider(endpoint: url, sessionToken: token).generateStreaming(input) { delta in
                if !Task.isCancelled { onDelta(delta) }
            }
        } else {
            result = try await DirectAIProvider(configuration: configuration, credential: token).generate(input)
        }
        try Task.checkCancellation()
        guard try await cacheScope(configuration) == auth.scope else { throw CancellationError() }
        return result
    }
}
