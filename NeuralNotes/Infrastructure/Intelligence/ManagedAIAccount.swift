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
        guard let session = await client.snapshot(), let url = ManagedAccountOverview.accountURL(studyURL: session.service.studyURL) else { return nil }
        let account = try await client.authorization(for: session.service.studyURL)
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        let response = try await ManagedNativeTransport().send(request)
        guard response.status == 200 else { throw response.status == 401 ? ManagedAIFailure.signedOut : ManagedAIFailure.unavailable }
        return try ManagedAccountOverview.decode(response.data)
    }
    static func isManaged(_ configuration: AIEngineConfiguration) async -> Bool {
        guard configuration.engine == .backend, let url = configuration.url else { return false }
        let current = await client.snapshot()
        return current?.service.studyURL == url || UserDefaults.standard.string(forKey: "ai.managed.endpoint") == url.absoluteString
    }
}
