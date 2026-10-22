import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ManagedAIFailure: Error, LocalizedError {
    case configuration, response, email, code, signedOut, rateLimited, unavailable
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Il servizio NeuralNotes non è ancora configurato per questa versione."
        case .response: return "Il servizio ha restituito una risposta non valida."
        case .email: return "Inserisci un indirizzo email valido."
        case .code: return "Il codice non è valido o è scaduto. Richiedine uno nuovo."
        case .signedOut: return "Accedi di nuovo al servizio NeuralNotes. Gli appunti locali restano disponibili."
        case .rateLimited: return "Attendi prima di riprovare: il servizio limita le richieste."
        case .unavailable: return "Servizio momentaneamente non disponibile. Riprova senza modificare gli appunti."
        }
    }
}

public struct ManagedAIService: Codable, Equatable, Sendable {
    public let studyURL: URL
    public let authURL: URL
    public let publicKey: String
    public static func configurationURL(studyURL: URL) throws -> URL {
        guard secure(studyURL), studyURL.path.hasSuffix("/v1/study") else { throw ManagedAIFailure.configuration }
        return studyURL.deletingLastPathComponent().appendingPathComponent("config")
    }
    public static func decode(_ data: Data, studyURL: URL) throws -> Self {
        struct Configuration: Decodable {
            struct Auth: Decodable { let url: URL; let publicKey: String }
            let version: Int; let managed: Bool; let auth: Auth?
        }
        _ = try configurationURL(studyURL: studyURL)
        guard data.count <= 65_536 else { throw ManagedAIFailure.response }
        let value = try JSONDecoder().decode(Configuration.self, from: data)
        guard value.version == 1, value.managed, let auth = value.auth,
              secure(auth.url), auth.url.path.isEmpty || auth.url.path == "/", validPublicKey(auth.publicKey) else { throw ManagedAIFailure.configuration }
        return Self(studyURL: studyURL, authURL: auth.url, publicKey: auth.publicKey)
    }
    public var isValid: Bool {
        Self.secure(studyURL) && studyURL.path.hasSuffix("/v1/study") && Self.secure(authURL)
            && (authURL.path.isEmpty || authURL.path == "/") && Self.validPublicKey(publicKey)
    }
    private static func validPublicKey(_ key: String) -> Bool {
        guard key.count <= 4096, !key.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }) else { return false }
        if key.hasPrefix("sb_publishable_"), key.count > 24 { return true }
        let pieces = key.split(separator: ".")
        guard pieces.count == 3 else { return false }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["role"] as? String == "anon"
    }
    private static func secure(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
    public func request(path: String, body: [String: String]?, bearer: String? = nil) throws -> URLRequest {
        guard isValid, ["otp", "verify", "token", "logout"].contains(path) else { throw ManagedAIFailure.configuration }
        var url = authURL.appendingPathComponent("auth/v1").appendingPathComponent(path)
        if path == "token" || path == "logout" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: path == "token" ? "grant_type" : "scope", value: path == "token" ? "refresh_token" : "local")]
            url = components.url!
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if path == "otp", let body { request.httpBody = try JSONSerialization.data(withJSONObject: ["email": body["email"] ?? "", "create_user": true]) }
        else if let body { request.httpBody = try JSONEncoder().encode(body) }
        return request
    }
}

public struct ManagedAISession: Codable, Equatable, Sendable {
    public let service: ManagedAIService
    public let userID: UUID
    public let email: String?
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public var isValid: Bool { service.isValid && Self.validToken(accessToken) && Self.validToken(refreshToken) && expiresAt.timeIntervalSince1970.isFinite }
    public static func decode(_ data: Data, service: ManagedAIService, now: Date, expectedUser: UUID? = nil) throws -> Self {
        struct Tokens: Decodable {
            struct User: Decodable { let id: UUID; let email: String?; let is_anonymous: Bool? }
            let access_token: String; let refresh_token: String; let token_type: String; let expires_in: Double; let user: User
        }
        guard data.count <= 65_536 else { throw ManagedAIFailure.response }
        let value = try JSONDecoder().decode(Tokens.self, from: data)
        guard service.isValid, value.token_type.lowercased() == "bearer", value.expires_in.isFinite,
              (60...604800).contains(value.expires_in), value.user.is_anonymous != true,
              expectedUser == nil || expectedUser == value.user.id,
              validToken(value.access_token), validToken(value.refresh_token) else { throw ManagedAIFailure.response }
        return Self(service: service, userID: value.user.id, email: value.user.email, accessToken: value.access_token, refreshToken: value.refresh_token, expiresAt: now.addingTimeInterval(value.expires_in))
    }
    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 8192 && !value.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 })
    }
}

public struct ManagedAIHTTPResponse: Sendable {
    public let data: Data; public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}
public protocol ManagedAITransport: Sendable { func send(_ request: URLRequest) async throws -> ManagedAIHTTPResponse }
public protocol ManagedAISessionStorage: Sendable {
    func load() throws -> ManagedAISession?
    func save(_ session: ManagedAISession?) throws
}

/// Owns refresh rotation and invalidates suspended work on logout or a service
/// change. Storage is injected so concurrency/recovery can be tested portably.
public actor ManagedAIClient {
    private let transport: any ManagedAITransport
    private let storage: any ManagedAISessionStorage
    private var session: ManagedAISession?
    private var service: ManagedAIService?
    private var generation = UUID()
    private var refresh: (id: UUID, task: Task<ManagedAISession, Error>)?
    public init(transport: any ManagedAITransport, storage: any ManagedAISessionStorage) {
        self.transport = transport; self.storage = storage
        if let saved = try? storage.load(), saved.isValid { session = saved; service = saved.service }
    }
    public func snapshot() -> ManagedAISession? { session }
    public func authorization(for studyURL: URL) async throws -> (token: String, userID: UUID) {
        let token = try await self.token(for: studyURL)
        guard let session, session.service.studyURL == studyURL, session.accessToken == token else { throw ManagedAIFailure.signedOut }
        return (token, session.userID)
    }
    public func connect(studyURL: URL) async throws -> ManagedAIService {
        let id = UUID(); generation = id; refresh?.task.cancel(); refresh = nil
        var request = URLRequest(url: try ManagedAIService.configurationURL(studyURL: studyURL)); request.timeoutInterval = 15
        let response = try await transport.send(request)
        try Self.check(response)
        let configured = try ManagedAIService.decode(response.data, studyURL: studyURL)
        guard generation == id, !Task.isCancelled else { throw CancellationError() }
        if session?.service != configured { try storage.save(nil); session = nil }
        service = configured; return configured
    }
    public func requestCode(email: String) async throws {
        guard let service else { throw ManagedAIFailure.configuration }
        let email = try Self.email(email), id = generation
        let response = try await transport.send(service.request(path: "otp", body: ["email": email]))
        try Self.check(response)
        guard generation == id, self.service == service, !Task.isCancelled else { throw CancellationError() }
    }
    public func verify(email: String, code: String, now: Date = Date()) async throws -> ManagedAISession {
        guard let service else { throw ManagedAIFailure.configuration }
        let email = try Self.email(email)
        guard (6...10).contains(code.count), code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw ManagedAIFailure.code }
        let id = UUID(); generation = id; refresh?.task.cancel(); refresh = nil
        let response = try await transport.send(service.request(path: "verify", body: ["email": email, "token": code, "type": "email"]))
        try Self.check(response)
        let value = try ManagedAISession.decode(response.data, service: service, now: now)
        guard generation == id, self.service == service, !Task.isCancelled else { throw CancellationError() }
        try storage.save(value); session = value; return value
    }
    public func token(for studyURL: URL, now: Date = Date()) async throws -> String {
        guard let current = session, current.service.studyURL == studyURL else { throw ManagedAIFailure.signedOut }
        if current.expiresAt.timeIntervalSince(now) > 60 { return current.accessToken }
        let id = generation
        let pending: (id: UUID, task: Task<ManagedAISession, Error>)
        if let refresh { pending = refresh }
        else {
            let task = Task { [transport] in
                let response = try await transport.send(current.service.request(path: "token", body: ["refresh_token": current.refreshToken]))
                try Self.check(response)
                return try ManagedAISession.decode(response.data, service: current.service, now: now, expectedUser: current.userID)
            }
            pending = (UUID(), task); refresh = pending
        }
        defer { if refresh?.id == pending.id { refresh = nil } }
        do {
            let rotated = try await pending.task.value
            guard generation == id else { throw CancellationError() }
            if session?.refreshToken == current.refreshToken { try storage.save(rotated); session = rotated }
            guard session?.accessToken == rotated.accessToken else { throw ManagedAIFailure.signedOut }
            try Task.checkCancellation()
            return rotated.accessToken
        } catch {
            if generation == id, let failure = error as? ManagedAIFailure, case .signedOut = failure {
                session = nil; try? storage.save(nil)
            }
            throw error
        }
    }
    public func signOut() async throws {
        generation = UUID(); refresh?.task.cancel(); refresh = nil
        let previous = session; session = nil; try storage.save(nil)
        if let previous {
            // A network failure must not restore credentials removed locally.
            _ = try? await transport.send(previous.service.request(path: "logout", body: nil, bearer: previous.accessToken))
        }
    }
    private static func email(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !value.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }) else { throw ManagedAIFailure.email }
        return value
    }
    private static func check(_ response: ManagedAIHTTPResponse) throws {
        guard response.data.count <= 65_536 else { throw ManagedAIFailure.response }
        switch response.status {
        case 200...299: return
        case 401, 403: throw ManagedAIFailure.signedOut
        case 400, 422: throw ManagedAIFailure.code
        case 429: throw ManagedAIFailure.rateLimited
        default: throw ManagedAIFailure.unavailable
        }
    }
}
