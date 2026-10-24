import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CloudSnapshot: Decodable, Equatable, Identifiable, Sendable {
    public let documentID: UUID
    public let revision: Int
    public let checksum: String
    public let bytes: Int64
    public let createdAt: Date?
    public var id: String { "\(documentID.uuidString):\(revision)" }
    enum CodingKeys: String, CodingKey { case documentID = "document_id", revision, checksum, bytes = "byte_size", createdAt = "created_at" }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        documentID = try v.decode(UUID.self, forKey: .documentID); revision = try v.decode(Int.self, forKey: .revision)
        checksum = try v.decode(String.self, forKey: .checksum); bytes = try v.decode(Int64.self, forKey: .bytes)
        createdAt = try v.decodeIfPresent(String.self, forKey: .createdAt).flatMap(CloudBackupWire.date)
        guard revision > 0, (1...CloudBackupQueue.maximumBytes).contains(bytes), AccountSyncCheckpoint.validDigest(checksum) else {
            throw CloudBackupFailure.invalidResponse
        }
    }
}

public extension CloudBackupWire {
    static func versions(studyURL: URL, token: String, documentID: UUID, offset: Int = 0) throws -> URLRequest {
        guard (0...10_000).contains(offset), offset.isMultiple(of: 50) else { throw CloudBackupFailure.invalidResponse }
        return try json(platformURL(studyURL: studyURL, path: "snapshots", query: [
            URLQueryItem(name: "document", value: documentID.uuidString.lowercased()), URLQueryItem(name: "offset", value: String(offset))]), token: token, body: nil)
    }
    static func snapshots(_ data: Data, documentID: UUID) throws -> [CloudSnapshot] {
        guard data.count <= 2 * 1024 * 1024, let values = try? JSONDecoder().decode([CloudSnapshot].self, from: data),
              values.count <= 50, values.allSatisfy({ $0.documentID == documentID }), Set(values.map(\.revision)).count == values.count else {
            throw CloudBackupFailure.invalidResponse
        }
        return values
    }
}
