import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NeuralNotesCore

private final class MemoryManagedSession: ManagedAISessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ManagedAISession?
    var failSave = false
    init(_ value: ManagedAISession? = nil) { self.value = value }
    func load() throws -> ManagedAISession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ session: ManagedAISession?) throws {
        lock.lock(); defer { lock.unlock() }
        if failSave { throw ManagedAIFailure.unavailable }; value = session
    }
}
private actor ManagedFixtureTransport: ManagedAITransport {
    var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) async throws -> ManagedAIHTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> ManagedAIHTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> ManagedAIHTTPResponse { requests.append(request); return try await handler(request) }
    func count(_ suffix: String) -> Int { requests.filter { $0.url!.path.hasSuffix(suffix) }.count }
}

final class ManagedAITests: XCTestCase {
    private let url = URL(string: "https://notes.example/pilot/v1/study")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let user = UUID(uuidString: "92f52aac-cb99-484b-9e07-de7ccc6f6441")!
    private static var configuration: Data { Data(#"{"version":1,"managed":true,"auth":{"url":"https://auth.example","publicKey":"sb_publishable_fixture_public_only"},"subscriptionsActive":false}"#.utf8) }
    private static func tokens(_ access: String = "access-one", refresh: String = "refresh-one", user: UUID = user, anonymous: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: ["access_token": access, "refresh_token": refresh, "token_type": "bearer", "expires_in": 3600, "user": ["id": user.uuidString, "email": "student@example.com", "is_anonymous": anonymous]])
    }
    private func session() throws -> ManagedAISession {
        try ManagedAISession.decode(Self.tokens(), service: ManagedAIService.decode(Self.configuration, studyURL: url), now: now)
    }
    func testManagedConfigurationPreservesGatewayPrefixAndRejectsUnsafeKeysAndURLs() throws {
        XCTAssertEqual(try ManagedAIService.configurationURL(studyURL: url).absoluteString, "https://notes.example/pilot/v1/config")
        let service = try ManagedAIService.decode(Self.configuration, studyURL: url)
        XCTAssertTrue(service.isValid)
        for raw in ["http://notes.example/v1/study", "https://secret@notes.example/v1/study", "https://notes.example/v1/study?token=secret", "https://notes.example/wrong"] {
            XCTAssertThrowsError(try ManagedAIService.configurationURL(studyURL: URL(string: raw)!))
        }
        for key in ["sb_secret_never_send_to_clients", "header." + Data(#"{"role":"service_role"}"#.utf8).base64EncodedString() + ".signature"] {
            let object: [String: Any] = ["version": 1, "managed": true, "auth": ["url": "https://auth.example", "publicKey": key]]
            XCTAssertThrowsError(try ManagedAIService.decode(JSONSerialization.data(withJSONObject: object), studyURL: url))
        }
    }
    func testOTPVerificationAndRefreshUseExpectedWireContractsWithoutSendingProviderSecrets() throws {
        let service = try ManagedAIService.decode(Self.configuration, studyURL: url)
        let otp = try service.request(path: "otp", body: ["email": "student@example.com"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: otp.httpBody!) as? [String: Any])
        XCTAssertEqual(body["create_user"] as? Bool, true); XCTAssertEqual(body["email"] as? String, "student@example.com")
        XCTAssertNil(otp.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(otp.url?.absoluteString, "https://auth.example/auth/v1/otp")
        let refresh = try service.request(path: "token", body: ["refresh_token": "fixture-refresh"])
        XCTAssertEqual(refresh.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(try service.request(path: "logout", body: nil, bearer: "fixture").url?.query, "scope=local")
    }
    func testSignInStoresSessionAndRejectsBadEmailOrCodeBeforeNetwork() async throws {
        let transport = ManagedFixtureTransport { request in
            .init(data: request.url!.path.hasSuffix("config") ? Self.configuration : request.url!.path.hasSuffix("verify") ? Self.tokens() : Data("{}".utf8), status: 200)
        }
        let storage = MemoryManagedSession(), client = ManagedAIClient(transport: transport, storage: storage)
        _ = try await client.connect(studyURL: url)
        do { try await client.requestCode(email: "bad\n@example.com"); XCTFail("Bad email") } catch ManagedAIFailure.email { }
        do { _ = try await client.verify(email: "student@example.com", code: "12"); XCTFail("Bad code") } catch ManagedAIFailure.code { }
        try await client.requestCode(email: "student@example.com")
        let saved = try await client.verify(email: "student@example.com", code: "123456", now: now)
        XCTAssertEqual(saved.userID, Self.user); XCTAssertEqual(try storage.load()?.refreshToken, "refresh-one")
        let token = try await client.token(for: url, now: now); XCTAssertEqual(token, "access-one")
        let count = await transport.count("verify"); XCTAssertEqual(count, 1)
        do { _ = try await client.token(for: URL(string: "https://other.example/v1/study")!, now: now); XCTFail("Cross service token") } catch ManagedAIFailure.signedOut { }
    }
    func testConcurrentRefreshRotatesOnlyOnceAndPersistsForNextLaunch() async throws {
        let storage = MemoryManagedSession(try session())
        let transport = ManagedFixtureTransport { _ in
            try await Task.sleep(for: .milliseconds(30))
            return .init(data: Self.tokens("access-two", refresh: "refresh-two"), status: 200)
        }
        let client = ManagedAIClient(transport: transport, storage: storage), expired = now.addingTimeInterval(3601)
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 { group.addTask { try await client.token(for: self.url, now: expired) } }
            var values: [String] = []; for try await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(Set(tokens), ["access-two"])
        let count = await transport.count("token"); XCTAssertEqual(count, 1)
        let restarted = ManagedAIClient(transport: transport, storage: storage)
        let restored = try await restarted.token(for: url, now: expired); XCTAssertEqual(restored, "access-two")
        XCTAssertEqual(try storage.load()?.refreshToken, "refresh-two")
    }
    func testLogoutDuringRefreshCannotResurrectCredentials() async throws {
        let storage = MemoryManagedSession(try session())
        let transport = ManagedFixtureTransport { request in
            if request.url!.path.hasSuffix("token") { try? await Task.sleep(for: .milliseconds(100)); return .init(data: Self.tokens("new", refresh: "new-refresh"), status: 200) }
            return .init(data: Data(), status: 204)
        }
        let client = ManagedAIClient(transport: transport, storage: storage)
        let pending = Task { try await client.token(for: url, now: now.addingTimeInterval(3601)) }
        for _ in 0..<200 {
            if await transport.count("token") > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let started = await transport.count("token"); XCTAssertEqual(started, 1)
        try await client.signOut()
        do { _ = try await pending.value; XCTFail("Logout must win") } catch is CancellationError { }
        let current = await client.snapshot(); XCTAssertNil(current); XCTAssertNil(try storage.load())
    }
    func testRevokedRefreshClearsSessionButTemporaryFailureKeepsIt() async throws {
        for status in [401, 503] {
            let storage = MemoryManagedSession(try session())
            let transport = ManagedFixtureTransport { _ in .init(data: Data("{}".utf8), status: status) }
            let client = ManagedAIClient(transport: transport, storage: storage)
            do { _ = try await client.token(for: url, now: now.addingTimeInterval(3601)); XCTFail("Refresh should fail") } catch { }
            XCTAssertEqual(try storage.load() == nil, status == 401)
        }
    }
    func testInvalidOrDifferentUserSessionCannotReplaceStoredIdentity() throws {
        let service = try session().service
        XCTAssertThrowsError(try ManagedAISession.decode(Self.tokens(anonymous: true), service: service, now: now))
        XCTAssertThrowsError(try ManagedAISession.decode(Self.tokens(user: UUID()), service: service, now: now, expectedUser: Self.user))
        XCTAssertThrowsError(try ManagedAISession.decode(Self.tokens("access\nbad"), service: service, now: now))
        XCTAssertThrowsError(try ManagedAISession.decode(Data(repeating: 65, count: 65_537), service: service, now: now))
    }
    func testStorageFailureDoesNotReportSuccessfulLogin() async throws {
        let storage = MemoryManagedSession()
        let transport = ManagedFixtureTransport { request in .init(data: request.url!.path.hasSuffix("config") ? Self.configuration : Self.tokens(), status: 200) }
        let client = ManagedAIClient(transport: transport, storage: storage)
        _ = try await client.connect(studyURL: url); storage.failSave = true
        do { _ = try await client.verify(email: "student@example.com", code: "123456"); XCTFail("Cannot persist credentials") } catch ManagedAIFailure.unavailable { }
        let current = await client.snapshot(); XCTAssertNil(current)
    }
    func testWebResearchCacheKeysAreSeparatedByAccountAndRemainValidStorageKeys() {
        var config = AIEngineConfiguration(); config.engine = .backend; config.endpoint = url.absoluteString
        let request = WebResearchRequest(term: "pressione arteriosa")
        let a = request.cacheKey(configuration: config, accountScope: "account-a")
        let b = request.cacheKey(configuration: config, accountScope: "account-b")
        XCTAssertNotEqual(a, b); XCTAssertEqual(a.count, 64); XCTAssertTrue(a.allSatisfy(\.isHexDigit))
        XCTAssertEqual(a, request.cacheKey(configuration: config, accountScope: "account-a"))
        XCTAssertNotEqual(a, request.cacheKey(configuration: config))
    }
    func testLogoutDuringVerificationCannotSignTheUserBackIn() async throws {
        let storage = MemoryManagedSession()
        let transport = ManagedFixtureTransport { request in
            if request.url!.path.hasSuffix("config") { return .init(data: Self.configuration, status: 200) }
            try? await Task.sleep(for: .milliseconds(100))
            return .init(data: Self.tokens(), status: 200)
        }
        let client = ManagedAIClient(transport: transport, storage: storage)
        _ = try await client.connect(studyURL: url)
        let pending = Task { try await client.verify(email: "student@example.com", code: "123456", now: now) }
        for _ in 0..<200 {
            if await transport.count("verify") > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let started = await transport.count("verify"); XCTAssertEqual(started, 1)
        try await client.signOut()
        do { _ = try await pending.value; XCTFail("Logout must win") } catch is CancellationError { }
        XCTAssertNil(try storage.load())
    }
}
