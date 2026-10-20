import Foundation

/// Versioned native package header. Large payloads will live in sibling directories.
/// Display metadata remains authoritative in the library database until native export (phase 3).
public struct DocumentManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let schemaVersion: Int
    public let documentID: UUID
    public let notebookID: UUID
    public let createdAt: Date
    public var pageIDs: [UUID]

    public init(documentID: UUID, notebookID: UUID, createdAt: Date = Date(), pageIDs: [UUID] = []) {
        self.schemaVersion = Self.currentVersion
        self.documentID = documentID
        self.notebookID = notebookID
        self.createdAt = createdAt
        self.pageIDs = pageIDs
    }
}
