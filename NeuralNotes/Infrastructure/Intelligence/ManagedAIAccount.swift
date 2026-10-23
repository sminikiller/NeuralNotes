import Foundation
import Security
import NeuralNotesCore

private final class ManagedKeychainStorage: ManagedAISessionStorage, @unchecked Sendable {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "NeuralNotes.ManagedAI", kSecAttrAccount as String: "session"] }
    func load() throws -> ManagedAISession? {
        var key = query; key[kSecReturnData as String] = true; key[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(key as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ManagedAIFailure.signedOut }
        return try JSONDecoder().decode(ManagedAISession.self, from: data)
    }
    func save(_ session: ManagedAISession?) throws {
        let key = query
        guard let session else {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ManagedAIFailure.signedOut }; return
        }
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ManagedAIFailure.signedOut }
        var value = key; value[kSecValueData as String] = data
        value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else { throw ManagedAIFailure.signedOut }
    }
}

private struct ManagedNativeTransport: ManagedAITransport {
    func send(_ request: URLRequest) async throws -> ManagedAIHTTPResponse {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ManagedAIFailure.response }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); guard data.count < 65_536 else { throw ManagedAIFailure.response }; data.append(byte) }
        return ManagedAIHTTPResponse(data: data, status: response.statusCode)
    }
}

@MainActor
enum ManagedAIAccount {
    static let client = ManagedAIClient(transport: ManagedNativeTransport(), storage: ManagedKeychainStorage())
    static var bundledStudyURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "NeuralNotesServiceURL") as? String,
              let root = URL(string: raw), root.scheme == "https", root.host != nil,
              root.query == nil, root.fragment == nil, root.user == nil, root.password == nil else { return nil }
        let url = root.appendingPathComponent("v1/study")
        return (try? ManagedAIService.configurationURL(studyURL: url)) != nil ? url : nil
    }
    /// Plan, limits and credits of the signed-in account; nil without a connected service.
    static func overview() async throws -> ManagedAccountOverview? {
        guard await client.snapshot() != nil else { return nil }
        let response = try await request(path: "account")
        return try ManagedAccountOverview.decode(response.data)
    }
    /// All account operations pin the identity across refresh and network awaits.
    private static func request(path: String, body: [String: String]? = nil, query: [URLQueryItem] = [], owner: ManagedAISession? = nil) async throws -> ManagedAIHTTPResponse {
        guard let original = await client.snapshot(),
              let url = ManagedAccountOverview.operationURL(studyURL: original.service.studyURL, path: path, query: query) else { throw ManagedAIFailure.signedOut }
        if let owner { guard original.userID == owner.userID, original.service == owner.service else { throw ManagedAIFailure.signedOut } }
        let auth = try await client.authorization(for: original.service.studyURL)
        guard auth.userID == original.userID else { throw ManagedAIFailure.signedOut }
        var request = URLRequest(url: url); request.timeoutInterval = 60
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let response = try await ManagedNativeTransport().send(request)
        guard let current = await client.snapshot(), current.userID == original.userID, current.service == original.service else { throw ManagedAIFailure.signedOut }
        if response.status == 401 { throw ManagedAIFailure.signedOut }
        if response.status == 409 { throw ManagedAccountFailure.sharedHub }
        guard (200...299).contains(response.status) else { throw ManagedAIFailure.unavailable }
        return response
    }
    static func updateProfile(_ name: String, owner: ManagedAISession) async throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(value.count) else { throw ManagedAIFailure.response }
        _ = try await request(path: "profile", body: ["displayName": value], owner: owner)
    }
    /// One resumable batch: true only after physical storage, metadata and Auth are removed.
    static func deleteAccount(owner: ManagedAISession) async throws -> Bool {
        let response = try await request(path: "account/delete", body: ["confirmation": "ELIMINA"], owner: owner)
        let result = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
        if response.status == 202, result?["pending"] as? Bool == true { return false }
        guard response.status == 200, result?["deleted"] as? Bool == true else { throw ManagedAIFailure.response }
        try await client.signOut(); CloudBackupService.shared.accountDidChange(); return true
    }
    static func exportMetadata() async throws -> URL {
        guard let original = await client.snapshot() else { throw ManagedAIFailure.signedOut }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-account-\(UUID()).json")
        try await ManagedAccountExport.write(userID: original.userID, email: original.email, to: file) { section, offset in
            let response = try await request(path: "account/export", query: [URLQueryItem(name: "section", value: section), URLQueryItem(name: "offset", value: String(offset))], owner: original)
            return response.data
        }
        return file
    }
    static func isManaged(_ configuration: AIEngineConfiguration) async -> Bool {
        guard configuration.engine == .backend, let url = configuration.url else { return false }
        let current = await client.snapshot()
        return current?.service.studyURL == url || UserDefaults.standard.string(forKey: "ai.managed.endpoint") == url.absoluteString
    }
}


enum ManagedAccountFailure: LocalizedError {
    case sharedHub
    var errorDescription: String? { "Un gruppo di cui sei proprietario contiene materiale di altri utenti. Trasferisci prima la proprietà; nessun materiale altrui è stato cancellato." }
}
