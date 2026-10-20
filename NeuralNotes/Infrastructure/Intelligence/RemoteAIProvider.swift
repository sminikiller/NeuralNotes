import Foundation
import Security
import NeuralNotesCore

enum AIConnectionFailure: LocalizedError {
    case configuration, response, invalidCitation, backend(String)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Configura un backend HTTPS e un token di sessione per usare l’AI remota."
        case .response: return "Il backend AI non ha restituito una risposta valida."
        case .invalidCitation: return "La risposta AI contiene riferimenti estranei alle fonti inviate."
        case .backend(let message): return message
        }
    }
}

/// Generic first-party backend contract. Provider credentials must remain on the
/// backend. This token authenticates the user to their backend, not to an LLM vendor.
struct RemoteAIProvider: AIProvider {
    let endpoint: URL
    let sessionToken: String

    func generate(_ request: AIRequest) async throws -> AIArtifact {
        guard endpoint.scheme == "https", endpoint.host != nil, !sessionToken.isEmpty else {
            throw AIConnectionFailure.configuration
        }
        var call = URLRequest(url: endpoint)
        call.httpMethod = "POST"; call.timeoutInterval = 90
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        call.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        call.httpBody = try JSONEncoder().encode(request)
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: call)
        guard let http = response as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else { throw AIConnectionFailure.response }
        if http.statusCode != 200 {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "Accesso AI non autorizzato o scaduto. Aggiorna il token della connessione."
            case 429: message = "Limite di richieste AI raggiunto. Riprova più tardi."
            case 413: message = "Le fonti selezionate sono troppo grandi. Scegli un ambito più piccolo."
            case 422: message = "Il provider non può elaborare questa richiesta. Prova a riformularla."
            case 504: message = "Il servizio AI ha impiegato troppo tempo. Puoi riprovare."
            default: message = "Il servizio AI non è disponibile. I tuoi appunti sono salvati sul dispositivo."
            }
            throw AIConnectionFailure.backend(message)
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(AIArtifact.self, from: data)
        let allowed = request.sources.map(\.reference)
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.sources.isEmpty || !result.references.isEmpty,
              result.references.allSatisfy({ allowed.contains($0) }) else { throw AIConnectionFailure.invalidCitation }
        return result
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum BackendCredentials {
    private static let service = "NeuralNotes.BackendSession"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIConnectionFailure.configuration }; return
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AIConnectionFailure.configuration }
        var value = query
        value[kSecValueData as String] = Data(token.utf8)
        value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else { throw AIConnectionFailure.configuration }
    }
}

struct FileDocumentIndexingService: DocumentIndexingService {
    let workspace: DocumentWorkspace
    let id: UUID
    func index(documentID: UUID) async throws -> [IndexedChunk] {
        guard documentID == id else { throw LibraryFailure.missingItem }
        return try await workspace.indexedChunks()
    }
}

/// Explicitly lexical retrieval, not an embedding or semantic search implementation.
struct LexicalRetrievalService: RetrievalService {
    func retrieve(question: String, from chunks: [IndexedChunk], limit: Int) async throws -> [IndexedChunk] {
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return chunks.enumerated().sorted { lhs, rhs in
            let left = terms.filter { lhs.element.text.lowercased().contains($0) }.count
            let right = terms.filter { rhs.element.text.lowercased().contains($0) }.count
            return left == right ? lhs.offset < rhs.offset : left > right
        }.prefix(max(0, limit)).map(\.element)
    }
}
