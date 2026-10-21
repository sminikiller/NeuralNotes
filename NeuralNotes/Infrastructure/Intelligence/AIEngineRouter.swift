import Foundation
import Security
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
        let call = try DirectAIWire.request(input, configuration: configuration, credential: credential)
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
        return try DirectAIWire.artifact(data, request: input, engine: configuration.engine)
    }
}

@MainActor
enum AIEngineRouter {
    static func research(_ input: WebResearchRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> AIArtifact {
        guard input.isValid, let url = configuration.researchURL else { throw AIWireFailure.configuration }
        let value: AIArtifact = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validatedWebResearch()
    }
    static func quiz(_ input: QuizRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> QuizBank {
        guard input.isValid, let url = configuration.quizURL else { throw AIWireFailure.configuration }
        let value: QuizBank = try await backendStructured(body: JSONEncoder().encode(input), url: url, configuration: configuration, consentKey: consentKey)
        return try value.validated(for: input)
    }
    private static func backendStructured<T: Decodable>(body: Data, url: URL, configuration: AIEngineConfiguration, consentKey: String?) async throws -> T {
        guard configuration.engine == .backend, consentKey == configuration.consentKey else { throw AIWireFailure.configuration }
        let credential = EngineCredentials.load(.backend); guard !credential.isEmpty else { throw AIWireFailure.configuration }
        var call = URLRequest(url: url); call.httpMethod = "POST"; call.timeoutInterval = 90
        call.setValue("application/json", forHTTPHeaderField: "Content-Type"); call.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization"); call.httpBody = body
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil); defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: call)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIConnectionFailure.backend("Richiesta non disponibile: controlla connessione, token e funzioni abilitate sul backend.") }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); guard data.count < DirectAIWire.maximumResponseBytes else { throw AIWireFailure.response }; data.append(byte) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(T.self, from: data)
    }
    static func lookup(_ input: LookupRequest, configuration: AIEngineConfiguration, consentKey: String?) async throws -> LookupCard {
        guard input.isValid, consentKey == configuration.consentKey, let url = configuration.lookupURL else { throw AIWireFailure.configuration }
        let credential = EngineCredentials.load(.backend)
        guard !credential.isEmpty else { throw AIWireFailure.configuration }
        var call = URLRequest(url: url); call.httpMethod = "POST"; call.timeoutInterval = 90
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        call.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization"); call.httpBody = try JSONEncoder().encode(input)
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: call)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIConnectionFailure.backend("Scheda non disponibile: controlla connessione, token e aggiornamento del backend /v1/lookup.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation(); guard data.count < DirectAIWire.maximumResponseBytes else { throw AIWireFailure.response }; data.append(byte)
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LookupCard.self, from: data).validated(for: input)
    }
    static func generate(_ input: AIRequest, configuration: AIEngineConfiguration, consentKey: String?, onDelta: @MainActor (String) -> Void = { _ in }) async throws -> AIArtifact {
        if configuration.engine == .offline { return try await ExtractiveStudyProvider().generate(input) }
        guard consentKey == configuration.consentKey, let url = configuration.url else { throw AIWireFailure.configuration }
        let token = EngineCredentials.load(configuration.engine)
        guard !token.isEmpty else { throw AIWireFailure.configuration }
        if configuration.engine == .backend {
            return try await RemoteAIProvider(endpoint: url, sessionToken: token).generateStreaming(input, onDelta: onDelta)
        }
        return try await DirectAIProvider(configuration: configuration, credential: token).generate(input)
    }
}
