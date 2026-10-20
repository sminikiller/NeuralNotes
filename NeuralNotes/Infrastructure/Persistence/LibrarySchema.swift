import Foundation
import SwiftData
import NeuralNotesCore

enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self] }

    @Model
    final class NotebookRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var documentID: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var folderID: UUID?
        var coverRawValue: String
        var isFavorite: Bool
        var deletedAt: Date?

        init(id: UUID, documentID: UUID, title: String, folderID: UUID?, cover: NotebookCover) {
            let now = Date()
            self.id = id
            self.documentID = documentID
            self.title = title
            self.createdAt = now
            self.updatedAt = now
            self.folderID = folderID
            self.coverRawValue = cover.rawValue
            self.isFavorite = false
            self.deletedAt = nil
        }

        var snapshot: Notebook {
            Notebook(id: id, documentID: documentID, title: title,
                     createdAt: createdAt, updatedAt: updatedAt, folderID: folderID,
                     cover: NotebookCover(rawValue: coverRawValue) ?? .midnight,
                     isFavorite: isFavorite)
        }
    }

    @Model
    final class FolderRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var parentID: UUID?

        init(title: String, parentID: UUID?) {
            self.id = UUID()
            self.title = title
            self.parentID = parentID
        }

        var snapshot: LibraryFolder { LibraryFolder(id: id, title: title, parentID: parentID) }
    }
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    // No prior release exists. Add and test a V1 -> V2 stage before changing persisted fields.
    static var stages: [MigrationStage] { [] }
}

typealias NotebookRecord = LibrarySchemaV1.NotebookRecord
typealias FolderRecord = LibrarySchemaV1.FolderRecord
