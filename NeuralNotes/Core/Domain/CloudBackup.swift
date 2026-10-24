import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CloudBackupFailure: Error, LocalizedError, Equatable {
    case tooLarge, conflict, quota, invalidResponse, unavailable, signedOut
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Il backup supera 100 MB, il limite per oggetto del cloud. Usa l’esportazione su File o il backup esterno."
        case .conflict: return "Nel cloud c’è una versione più recente di questo quaderno. Scaricala come copia oppure salva sostituendo la versione del cloud."
        case .quota: return "Spazio cloud del piano esaurito. Elimina copie o usa il backup su File."
        case .invalidResponse: return "Il servizio cloud ha risposto in modo non valido. Il quaderno locale non è cambiato."
        case .unavailable: return "Servizio cloud non raggiungibile. Il backup resta in coda e riparte al prossimo tentativo."
        case .signedOut: return "Accedi all’account NeuralNotes per usare il backup nel cloud."
        }
    }
}

/// A notebook copy kept by the NeuralNotes service. Every commit keeps the previous
/// revision as an immutable snapshot on the server.
public struct CloudDocument: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let revision: Int
    public let title: String
    public let checksum: String?
    public let bytes: Int64
    public let deleted: Bool
    public let updatedAt: Date?
    enum CodingKeys: String, CodingKey { case id, revision, title, checksum, bytes = "byte_size", deleted, updatedAt = "updated_at" }
    public init(id: UUID, revision: Int, title: String, checksum: String?, bytes: Int64, deleted: Bool, updatedAt: Date?) {
        self.id = id; self.revision = revision; self.title = title; self.checksum = checksum; self.bytes = bytes; self.deleted = deleted; self.updatedAt = updatedAt
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); revision = try values.decode(Int.self, forKey: .revision)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""; checksum = try values.decodeIfPresent(String.self, forKey: .checksum)
        bytes = try values.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0; deleted = try values.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt).flatMap(CloudBackupWire.date)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(revision, forKey: .revision); try values.encode(title, forKey: .title)
        try values.encodeIfPresent(checksum, forKey: .checksum); try values.encode(bytes, forKey: .bytes); try values.encode(deleted, forKey: .deleted)
        try values.encodeIfPresent(updatedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .updatedAt)
    }
    public var isValid: Bool {
        revision >= 0 && title.count <= 160 && bytes >= 0 && bytes <= CloudBackupQueue.maximumBytes
            && (checksum.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true)
    }
}

public enum CloudBackupStage: String, Codable, Sendable { case prepared, reserved, uploaded }

/// One pending upload. The archive file stays in the queue folder until the
/// commit succeeds, so a lost connection or a closed app resumes where it stopped.
public struct CloudBackupJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { documentID }
    public let documentID: UUID
    public var title: String
    public var archiveFile: String
    public var checksum: String
    public var bytes: Int64
    public var stage: CloudBackupStage
    public var objectPath: String?
    public var expectedRevision: Int
    public var replaceNewer: Bool
    public var attempts: Int
    public var lastError: String?
    /// The cloud has a newer revision: nothing is replaced until the student decides.
    public var conflict: Bool
    public var createdAt: Date
    public init(documentID: UUID, title: String, archiveFile: String, checksum: String, bytes: Int64, expectedRevision: Int, replaceNewer: Bool = false, now: Date = Date()) {
        self.documentID = documentID; self.title = String(title.replacingOccurrences(of: "\n", with: " ").prefix(160)); self.archiveFile = archiveFile
        self.checksum = checksum; self.bytes = bytes; stage = .prepared; objectPath = nil; self.expectedRevision = max(0, expectedRevision)
        self.replaceNewer = replaceNewer; attempts = 0; lastError = nil; conflict = false; createdAt = now
    }
    public var isValid: Bool {
        !title.isEmpty && title.count <= 160 && checksum.count == 64 && checksum.allSatisfy(\.isHexDigit)
            && (1...CloudBackupQueue.maximumBytes).contains(bytes) && expectedRevision >= 0 && attempts >= 0
            && !archiveFile.isEmpty && !archiveFile.contains("/") && !archiveFile.contains("..")
            && (stage == .prepared) == (objectPath == nil)
    }
}

/// A cloud queue belongs to both a user and a gateway; neither is interchangeable.
public struct CloudBackupOwner: Codable, Equatable, Sendable {
    public let studyURL: URL
    public let userID: UUID
    public init(studyURL: URL, userID: UUID) { self.studyURL = studyURL; self.userID = userID }
}

public struct CloudBackupQueue: Codable, Equatable, Sendable {
    public static let maximumBytes: Int64 = 104_857_600
    public var owner: CloudBackupOwner?
    public var jobs: [CloudBackupJob] = []
    /// Last cloud revision this device committed or downloaded, per document.
    public var revisions: [UUID: Int] = [:]
    public init(owner: CloudBackupOwner? = nil) { self.owner = owner }
    public func canResume(for account: CloudBackupOwner) -> Bool {
        owner == account && jobs.allSatisfy(\.isValid)
    }
    /// A newer copy of the same notebook replaces the waiting one; its archive can be removed.
    @discardableResult
    public mutating func enqueue(_ job: CloudBackupJob) throws -> CloudBackupJob? {
        guard job.isValid else { throw job.bytes > Self.maximumBytes ? CloudBackupFailure.tooLarge : CloudBackupFailure.invalidResponse }
        let replaced = jobs.first { $0.documentID == job.documentID }
        jobs.removeAll { $0.documentID == job.documentID }; jobs.append(job)
        return replaced
    }
    public mutating func update(_ job: CloudBackupJob) { if let index = jobs.firstIndex(where: { $0.documentID == job.documentID }) { jobs[index] = job } }
    public mutating func complete(_ documentID: UUID, revision: Int) {
        jobs.removeAll { $0.documentID == documentID }; revisions[documentID] = revision
    }
    public mutating func drop(_ documentID: UUID) { jobs.removeAll { $0.documentID == documentID } }
}

/// Requests to the gateway's platform endpoints and to the private storage they
/// authorize. The user's bearer token is only ever sent to the gateway or to the
/// storage host the account was configured with.
public enum CloudBackupWire {
    public static func platformURL(studyURL: URL, path: String, query: [URLQueryItem] = []) -> URL? {
        guard studyURL.scheme == "https", studyURL.path.hasSuffix("/v1/study"), ["uploads", "commit", "documents", "download", "snapshots"].contains(path),
              var parts = URLComponents(url: studyURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("study".count)) + "platform/" + path
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url
    }
    static func json(_ url: URL?, token: String, body: [String: Any]?) throws -> URLRequest {
        guard let url, !token.isEmpty, !token.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) else { throw CloudBackupFailure.signedOut }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }
    public static func reserve(studyURL: URL, token: String, job: CloudBackupJob) throws -> URLRequest {
        guard job.isValid else { throw CloudBackupFailure.tooLarge }
        return try json(platformURL(studyURL: studyURL, path: "uploads"), token: token,
                        body: ["kind": "cloud", "entityID": job.documentID.uuidString.lowercased(), "extension": "nnbackup", "bytes": job.bytes])
    }
    public static func reservation(_ data: Data, service: ManagedAIService, job: CloudBackupJob) throws -> (objectPath: String, uploadURL: URL) {
        struct Value: Decodable { let objectPath: String; let method: String; let uploadURL: URL; let publicKey: String; let expectedBytes: Int64; let requiresUserBearer: Bool; let upsert: Bool }
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(Value.self, from: data), value.method == "POST",
              value.expectedBytes == job.bytes, value.requiresUserBearer, !value.upsert, value.publicKey == service.publicKey,
              validObject(value.objectPath, documentID: job.documentID), storage(value.uploadURL, service: service, prefix: "/storage/v1/object/neuralnotes-private/")
        else { throw CloudBackupFailure.invalidResponse }
        return (value.objectPath, value.uploadURL)
    }
    /// The storage path reserved for a job, on the storage host of the signed-in account.
    public static func uploadURL(service: ManagedAIService, objectPath: String, documentID: UUID) throws -> URL {
        guard validObject(objectPath, documentID: documentID), var parts = URLComponents(url: service.authURL, resolvingAgainstBaseURL: false) else { throw CloudBackupFailure.invalidResponse }
        parts.path = "/storage/v1/object/neuralnotes-private/" + objectPath; parts.query = nil
        guard let url = parts.url, storage(url, service: service, prefix: "/storage/v1/object/neuralnotes-private/") else { throw CloudBackupFailure.invalidResponse }
        return url
    }
    /// Authenticated upload to the reserved path: never an upsert, never an anonymous token.
    public static func upload(_ url: URL, token: String, service: ManagedAIService) throws -> URLRequest {
        guard storage(url, service: service, prefix: "/storage/v1/object/neuralnotes-private/") else { throw CloudBackupFailure.invalidResponse }
        var request = try json(url, token: token, body: nil); request.httpMethod = "POST"; request.timeoutInterval = 600
        request.setValue(service.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        return request
    }
    public static func commit(studyURL: URL, token: String, job: CloudBackupJob) throws -> URLRequest {
        guard job.isValid, let objectPath = job.objectPath, job.stage == .uploaded else { throw CloudBackupFailure.invalidResponse }
        return try json(platformURL(studyURL: studyURL, path: "commit"), token: token,
                        body: ["documentID": job.documentID.uuidString.lowercased(), "expectedRevision": job.expectedRevision, "title": job.title,
                               "objectPath": objectPath, "checksum": job.checksum, "bytes": job.bytes, "deleted": false])
    }
    public static func committed(_ data: Data, job: CloudBackupJob) throws -> CloudDocument {
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(CloudDocument.self, from: data), value.isValid,
              value.id == job.documentID, value.revision == job.expectedRevision + 1, value.checksum == job.checksum, value.bytes == job.bytes else { throw CloudBackupFailure.invalidResponse }
        return value
    }
    public static func list(studyURL: URL, token: String, offset: Int = 0) throws -> URLRequest {
        guard (0...10_000).contains(offset), offset.isMultiple(of: 50) else { throw CloudBackupFailure.invalidResponse }
        return try json(platformURL(studyURL: studyURL, path: "documents", query: offset == 0 ? [] : [URLQueryItem(name: "offset", value: String(offset))]), token: token, body: nil)
    }
    public static func documents(_ data: Data) throws -> [CloudDocument] {
        guard data.count <= 2 * 1024 * 1024, let values = try? JSONDecoder().decode([CloudDocument].self, from: data),
              values.count <= 50, values.allSatisfy(\.isValid) else { throw CloudBackupFailure.invalidResponse }
        return values
    }
    public static func download(studyURL: URL, token: String, documentID: UUID, revision: Int? = nil) throws -> URLRequest {
        var query = [URLQueryItem(name: "document", value: documentID.uuidString.lowercased())]
        if let revision { guard revision > 0 else { throw CloudBackupFailure.invalidResponse }; query.append(URLQueryItem(name: "revision", value: String(revision))) }
        return try json(platformURL(studyURL: studyURL, path: "download", query: query), token: token, body: nil)
    }
    public static func downloadURL(_ data: Data, service: ManagedAIService) throws -> URL {
        struct Value: Decodable { let url: URL; let expiresIn: Int }
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(Value.self, from: data), (1...600).contains(value.expiresIn),
              storage(value.url, service: service, prefix: "/storage/v1/object/sign/neuralnotes-private/") else { throw CloudBackupFailure.invalidResponse }
        return value.url
    }
    /// Maps gateway errors: a revision conflict keeps both versions on the server.
    public static func failure(status: Int) -> CloudBackupFailure {
        switch status {
        case 409: return .conflict
        case 429: return .quota
        case 401: return .signedOut
        case 413: return .tooLarge
        default: return .unavailable
        }
    }
    /// PostgreSQL timestamps carry microseconds; ISO 8601 parsing needs at most milliseconds.
    static func date(_ value: String) -> Date? {
        var text = value
        if let dot = text.firstIndex(of: "."), let end = text[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) {
            let digits = text.index(after: dot)..<end
            let kept = String(text[digits].prefix(3))
            if text[digits].count > 3 { text.replaceSubrange(digits, with: kept) }
        }
        let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    private static func validObject(_ path: String, documentID: UUID) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, !path.contains(".."), UUID(uuidString: parts[0]) != nil, parts[1] == "cloud",
              parts[2] == documentID.uuidString.lowercased(), parts[3].hasSuffix(".nnbackup"),
              UUID(uuidString: String(parts[3].dropLast(".nnbackup".count))) != nil else { return false }
        return true
    }
    private static func storage(_ url: URL, service: ManagedAIService, prefix: String) -> Bool {
        url.scheme == "https" && url.host != nil && url.host == service.authURL.host && url.port == service.authURL.port
            && url.user == nil && url.password == nil && url.fragment == nil && url.path.hasPrefix(prefix) && !url.path.contains("..")
    }
}
