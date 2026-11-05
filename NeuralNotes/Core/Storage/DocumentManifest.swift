import Foundation

/// Versioned native package header. Large payloads will live in sibling directories.
/// Display metadata remains authoritative in the library database until native export (phase 3).
public struct DocumentManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let layersVersion = 2
    public static func supports(_ version: Int) -> Bool { (currentVersion...layersVersion).contains(version) }
    public let schemaVersion: Int
    public let documentID: UUID
    public let notebookID: UUID
    public let createdAt: Date
    public var pageIDs: [UUID]

    public init(documentID: UUID, notebookID: UUID, createdAt: Date = Date(), pageIDs: [UUID] = [], schemaVersion: Int = Self.currentVersion) {
        self.schemaVersion = schemaVersion
        self.documentID = documentID
        self.notebookID = notebookID
        self.createdAt = createdAt
        self.pageIDs = pageIDs
    }

    func retainingFormat(atLeast version: Int) -> DocumentManifest {
        DocumentManifest(documentID: documentID, notebookID: notebookID, createdAt: createdAt,
            pageIDs: pageIDs, schemaVersion: max(schemaVersion, version))
    }
}
