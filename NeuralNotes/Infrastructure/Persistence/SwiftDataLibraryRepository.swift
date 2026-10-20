import Foundation
import SwiftData
import NeuralNotesCore
import UniformTypeIdentifiers

@MainActor
final class SwiftDataLibraryRepository: LibraryRepository {
    private let context: ModelContext
    private let documents: NativeDocumentStore
    private var workspaces: [UUID: DocumentWorkspace] = [:]

    init(container: ModelContainer, documents: NativeDocumentStore) {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.documents = documents
    }

    func notebooks() throws -> [Notebook] {
        try allRecords().filter { $0.deletedAt == nil }.map(\.snapshot)
    }

    func folders() throws -> [LibraryFolder] {
        try context.fetch(FetchDescriptor<FolderRecord>()).map(\.snapshot)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func trashedNotebooks() throws -> [Notebook] {
        try allRecords().filter { $0.deletedAt != nil }.map(\.snapshot)
    }

    func createNotebook(title: String, folderID: UUID?, cover: NotebookCover, template: PageTemplate? = nil) throws -> Notebook {
        let name = try LibraryName.validated(title)
        try validateFolder(folderID)
        let record = NotebookRecord(id: UUID(), documentID: UUID(), title: name, folderID: folderID, cover: cover)
        let manifest = DocumentManifest(documentID: record.documentID, notebookID: record.id)
        try documents.create(manifest, template: template)
        context.insert(record)
        do { try commit() }
        catch {
            let original = error
            do { try documents.removeUncommitted(documentID: manifest.documentID) }
            catch { throw LibraryFailure.recoveryRequired(original.localizedDescription) }
            throw original
        }
        return record.snapshot
    }

    func updateNotebook(id: UUID, title: String, folderID: UUID?, cover: NotebookCover) throws {
        let name = try LibraryName.validated(title)
        try validateFolder(folderID)
        let record = try notebook(id)
        record.title = name
        record.folderID = folderID
        record.coverRawValue = cover.rawValue
        record.updatedAt = Date()
        try commit()
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        let record = try notebook(id)
        record.isFavorite = isFavorite
        try commit()
    }
    func touchNotebook(id: UUID) throws {
        let record = try notebook(id); record.updatedAt = Date(); try commit()
    }

    func duplicateNotebook(id: UUID) async throws -> Notebook {
        let source = try notebook(id)
        let title = String(source.title.prefix(113)) + " (copia)"
        let copy = NotebookRecord(id: UUID(), documentID: UUID(), title: title, folderID: source.folderID,
                                  cover: NotebookCover(rawValue: source.coverRawValue) ?? .midnight)
        let documentID = copy.documentID
        let workspace = try workspace(id: id)
        try await workspace.clone(to: documents, documentID: documentID, notebookID: copy.id)
        do { try validateFolder(copy.folderID); context.insert(copy); try commit() }
        catch {
            let original = error
            do { try documents.removeUncommitted(documentID: documentID) }
            catch { throw LibraryFailure.recoveryRequired(original.localizedDescription) }
            throw original
        }
        return copy.snapshot
    }

    func deleteNotebook(id: UUID) throws {
        let record = try notebook(id)
        guard !EditorLeases.shared.isOpen(record.documentID) else {
            throw LibraryFailure.recoveryRequired("Chiudi il quaderno nelle finestre prima di spostarlo nel cestino.")
        }
        record.deletedAt = Date()
        record.updatedAt = Date()
        // Tombstones preserve packages and allow recovery; physical purge is not part of phase 1.
        try commit()
    }

    func importNotebook(from url: URL, folderID: UUID?) async throws -> Notebook {
        try validateFolder(folderID)
        let documentID = UUID(), notebookID = UUID(), store = documents
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if url.pathExtension.lowercased() == "pdf" || contentType?.conforms(to: .pdf) == true {
            try Task.checkCancellation()
            let manifest = DocumentManifest(documentID: documentID, notebookID: notebookID)
            try documents.create(manifest)
            do {
                let writer = DocumentWorkspace(package: documents.packageURL(for: documentID), documentID: documentID, notebookID: notebookID)
                _ = try await DocumentServices.importPDF(from: url, into: writer)
                try validateFolder(folderID)
                let name = String(url.deletingPathExtension().lastPathComponent.prefix(120))
                let record = NotebookRecord(id: notebookID, documentID: documentID,
                    title: try LibraryName.validated(name.isEmpty ? "PDF importato" : name), folderID: folderID, cover: .lagoon)
                context.insert(record); try commit(); workspaces[notebookID] = writer
                return record.snapshot
            } catch {
                let failure = error
                do { try documents.removeUncommitted(documentID: documentID) }
                catch { throw LibraryFailure.recoveryRequired(failure.localizedDescription) }
                throw failure
            }
        }
        let job = Task.detached(priority: .userInitiated) {
            try NativeImport.copy(from: url, into: store, documentID: documentID, notebookID: notebookID)
        }
        let metadata = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        do {
            try validateFolder(folderID)
            let title = try LibraryName.validated(metadata?.title ?? "Quaderno importato")
            let record = NotebookRecord(id: notebookID, documentID: documentID, title: title,
                folderID: folderID, cover: metadata?.cover ?? .lagoon)
            context.insert(record); try commit()
            return record.snapshot
        } catch {
            let original = error
            do { try documents.removeUncommitted(documentID: documentID) }
            catch { throw LibraryFailure.recoveryRequired(original.localizedDescription) }
            throw original
        }
    }

    func restoreNotebook(id: UUID) throws {
        guard let record = try allRecords().first(where: { $0.id == id && $0.deletedAt != nil }) else {
            throw LibraryFailure.missingItem
        }
        // A formerly empty folder may have been deleted after the notebook was removed.
        if let folderID = record.folderID, !(try folders()).contains(where: { $0.id == folderID }) {
            record.folderID = nil
        }
        record.deletedAt = nil
        record.updatedAt = Date()
        try commit()
    }

    func createFolder(title: String, parentID: UUID?) throws {
        let name = try LibraryName.validated(title)
        try validateFolder(parentID)
        context.insert(FolderRecord(title: name, parentID: parentID))
        try commit()
    }

    func renameFolder(id: UUID, title: String) throws {
        let name = try LibraryName.validated(title)
        let record = try folder(id)
        record.title = name
        try commit()
    }

    func deleteFolder(id: UUID) throws {
        let record = try folder(id)
        guard !(try folders()).contains(where: { $0.parentID == id }),
              !(try notebooks()).contains(where: { $0.folderID == id }) else {
            throw LibraryFailure.nonEmptyFolder
        }
        context.delete(record)
        try commit()
    }

    func openNotebook(id: UUID) throws -> DocumentManifest {
        let record = try notebook(id)
        return try documents.read(documentID: record.documentID, notebookID: record.id)
    }

    func workspace(id: UUID) throws -> DocumentWorkspace {
        let record = try notebook(id)
        _ = try documents.read(documentID: record.documentID, notebookID: record.id)
        if let existing = workspaces[id] { return existing }
        let writer = DocumentWorkspace(package: documents.packageURL(for: record.documentID),
                                       documentID: record.documentID, notebookID: record.id)
        workspaces[id] = writer
        return writer
    }

    func integrityReport() throws -> [String] {
        let records = try allRecords()
        var issues: [String] = []
        for record in records where record.deletedAt == nil {
            do { _ = try documents.read(documentID: record.documentID, notebookID: record.id) }
            catch { issues.append("\(record.title): \(error.localizedDescription)") }
        }
        let orphans = try documents.unreferencedPackages(referencedDocumentIDs: Set(records.map(\.documentID)))
        if !orphans.isEmpty {
            issues.append("\(orphans.count) quaderni conservati senza riferimento. Apri Recupero quaderni nella sidebar.")
        }
        return issues
    }

    func recoverablePackages() throws -> [URL] {
        try documents.unreferencedPackages(referencedDocumentIDs: Set(allRecords().map(\.documentID)))
    }
    func repairNotebookIndex(id: UUID) throws {
        guard !EditorLeases.shared.isOpen(try notebook(id).documentID) else {
            throw LibraryFailure.recoveryRequired("Chiudi il quaderno nelle finestre prima del recupero.")
        }
        let record = try notebook(id)
        try documents.restorePreviousManifest(documentID: record.documentID, notebookID: record.id)
    }

    func recoverPackage(_ url: URL) async throws {
        guard try recoverablePackages().contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { throw LibraryFailure.missingItem }
        let inspected = try await Task.detached(priority: .utility) { try NativePackageInspector.inspect(url) }.value
        let manifest = inspected.manifest
        guard documents.packageURL(for: manifest.documentID).standardizedFileURL == url.standardizedFileURL,
              !(try allRecords()).contains(where: { $0.id == manifest.notebookID || $0.documentID == manifest.documentID }) else {
            throw LibraryFailure.corruptDocument
        }
        let record = NotebookRecord(id: manifest.notebookID, documentID: manifest.documentID,
            title: try LibraryName.validated(inspected.metadata?.title ?? "Quaderno recuperato"), folderID: nil,
            cover: inspected.metadata?.cover ?? .lagoon)
        context.insert(record); try commit()
    }

    private func allRecords() throws -> [NotebookRecord] {
        try context.fetch(FetchDescriptor<NotebookRecord>())
    }

    private func notebook(_ id: UUID) throws -> NotebookRecord {
        guard let record = try allRecords().first(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw LibraryFailure.missingItem
        }
        return record
    }

    private func folder(_ id: UUID) throws -> FolderRecord {
        guard let record = try context.fetch(FetchDescriptor<FolderRecord>()).first(where: { $0.id == id }) else {
            throw LibraryFailure.missingItem
        }
        return record
    }

    private func validateFolder(_ id: UUID?) throws {
        if let id { _ = try folder(id) }
    }

    private func commit() throws {
        do { try context.save(); LibraryRevision.shared.value += 1 }
        catch { context.rollback(); throw error }
    }
}
