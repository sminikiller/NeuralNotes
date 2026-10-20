import Foundation
import Observation
import NeuralNotesCore

enum LibraryScope: Hashable {
    case all, favorites, trash, folder(UUID)
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified = "Ultima modifica", name = "Nome", created = "Data di creazione"
    var id: String { rawValue }
}

struct CatalogRecoveryItem: Identifiable {
    let notebook: Notebook
    let canRestore: Bool
    var id: UUID { notebook.id }
}

@MainActor @Observable
final class LibraryViewModel {
    private let repository: any LibraryRepository
    private(set) var notebooks: [Notebook] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var trash: [Notebook] = []
    var scope: LibraryScope? = .all
    var query = ""
    var sort = LibrarySort.modified
    var errorMessage: String?
    var integrityIssues: [String] = []
    var lastDeletedID: UUID?
    var importing = false
    var coverRevision = 0
    var recentIDs: [UUID] = UserDefaults.standard.stringArray(forKey: "library.recentNotebookIDs")?.compactMap(UUID.init(uuidString:)) ?? []
    var recentNotebooks: [Notebook] {
        let available = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0) })
        return Array(recentIDs.compactMap { available[$0] }.prefix(5))
    }
    func markOpened(_ notebook: Notebook) {
        recentIDs.removeAll { $0 == notebook.id }; recentIDs.insert(notebook.id, at: 0); recentIDs = Array(recentIDs.prefix(12))
        UserDefaults.standard.set(recentIDs.map(\.uuidString), forKey: "library.recentNotebookIDs")
    }

    init(repository: any LibraryRepository) { self.repository = repository }

    var currentFolderID: UUID? {
        if case .folder(let id) = scope ?? .all { return id }
        return nil
    }

    var title: String {
        switch scope ?? .all {
        case .all: return "La tua libreria"
        case .favorites: return "Preferiti"
        case .trash: return "Cestino"
        case .folder(let id): return folders.first { $0.id == id }?.title ?? "Cartella"
        }
    }

    var visibleNotebooks: [Notebook] {
        (scope == .trash ? trash : notebooks).filter { notebook in
            let inScope: Bool
            switch scope ?? .all {
            case .all: inScope = true
            case .favorites: inScope = notebook.isFavorite
            case .trash: inScope = true
            case .folder(let id): inScope = notebook.folderID == id
            }
            return inScope && (query.isEmpty || notebook.title.localizedStandardContains(query))
        }.sorted { lhs, rhs in
            switch sort {
            case .name:
                let order = lhs.title.localizedStandardCompare(rhs.title)
                return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
            case .modified: return lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
            case .created: return lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt > rhs.createdAt
            }
        }
    }

    var folderRows: [(folder: LibraryFolder, depth: Int)] {
        var result: [(LibraryFolder, Int)] = []
        var visited = Set<UUID>()
        func appendChildren(of parent: UUID?, depth: Int) {
            for folder in folders where folder.parentID == parent && !visited.contains(folder.id) {
                visited.insert(folder.id)
                result.append((folder, depth))
                appendChildren(of: folder.id, depth: depth + 1)
            }
        }
        appendChildren(of: nil, depth: 0)
        return result
    }

    func reload() throws {
        let newNotebooks = try repository.notebooks()
        let newFolders = try repository.folders()
        let deleted = try repository.trashedNotebooks()
        notebooks = newNotebooks
        folders = newFolders
        trash = deleted
    }

    @discardableResult
    func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); try reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func create(title: String, cover: NotebookCover, folderID: UUID?, template: PageTemplate? = nil) -> Bool {
        perform {
            _ = try repository.createNotebook(title: title, folderID: folderID, cover: cover, template: template)
            // Keep the new notebook visible even when creation started from Favorites/search.
            scope = folderID.map(LibraryScope.folder) ?? .all
            query = ""
        }
    }

    func update(_ notebook: Notebook, title: String, cover: NotebookCover, folderID: UUID?) -> Bool {
        perform { try repository.updateNotebook(id: notebook.id, title: title, folderID: folderID, cover: cover) }
    }

    func toggleFavorite(_ notebook: Notebook) {
        perform { try repository.setFavorite(id: notebook.id, isFavorite: !notebook.isFavorite) }
    }

    func duplicate(_ notebook: Notebook) async {
        do {
            _ = try await repository.duplicateNotebook(id: notebook.id)
            scope = notebook.folderID.map(LibraryScope.folder) ?? .all
            query = ""
            try reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func importNotebook(from url: URL) async {
        guard !importing else { return }
        importing = true; defer { importing = false }
        do {
            let notebook = try await repository.importNotebook(from: url, folderID: currentFolderID)
            scope = notebook.folderID.map(LibraryScope.folder) ?? .all; query = ""
            try reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ notebook: Notebook) {
        perform {
            try repository.deleteNotebook(id: notebook.id)
            lastDeletedID = notebook.id
        }
    }

    func restoreLastDeleted() {
        guard let id = lastDeletedID else { return }
        perform { try repository.restoreNotebook(id: id); lastDeletedID = nil }
    }

    func restore(_ notebook: Notebook) {
        perform { try repository.restoreNotebook(id: notebook.id) }
    }

    func createFolder(title: String, parentID: UUID?) -> Bool {
        perform { try repository.createFolder(title: title, parentID: parentID) }
    }

    func renameFolder(_ folder: LibraryFolder, title: String) -> Bool {
        perform { try repository.renameFolder(id: folder.id, title: title) }
    }

    func deleteFolder(_ folder: LibraryFolder) {
        perform {
            try repository.deleteFolder(id: folder.id)
            if currentFolderID == folder.id { scope = .all }
        }
    }

    func open(_ notebook: Notebook) throws -> DocumentManifest {
        try repository.openNotebook(id: notebook.id)
    }

    func workspace(_ notebook: Notebook) throws -> DocumentWorkspace { try repository.workspace(id: notebook.id) }
    func installCloudArchive(_ url: URL, expectedLocal: String?, expectedRemote: String) async throws -> Notebook {
        guard let native = repository as? SwiftDataLibraryRepository else { throw LibraryFailure.missingItem }
        let book = try await native.installCloudArchive(url, expectedLocal: expectedLocal, expectedRemote: expectedRemote); try reload(); return book
    }
    func recoverablePackages() throws -> [URL] { try repository.recoverablePackages() }
    func recover(_ url: URL) async throws { try await repository.recoverPackage(url); try reload() }
    func damagedNotebooks() -> [Notebook] { notebooks.filter { (try? repository.openNotebook(id: $0.id)) == nil } }
    func repair(_ notebook: Notebook) throws { try repository.repairNotebookIndex(id: notebook.id); try reload() }
    func catalogRecoveryItems() async -> [CatalogRecoveryItem] {
        var items: [CatalogRecoveryItem] = []
        for notebook in notebooks {
            guard let workspace = try? repository.workspace(id: notebook.id),
                  let status = try? await workspace.catalogRecoveryStatus(), status.needsRecovery else { continue }
            items.append(CatalogRecoveryItem(notebook: notebook, canRestore: status.canRestore))
        }
        return items
    }
    func repairCatalog(_ notebook: Notebook) async throws {
        guard !EditorLeases.shared.isOpen(notebook.documentID) else {
            throw LibraryFailure.recoveryRequired("Chiudi il quaderno nelle finestre prima del recupero.")
        }
        try await repository.workspace(id: notebook.id).restorePreviousCatalog()
        try reload()
    }

    func didEdit(_ notebook: Notebook) {
        perform { try repository.touchNotebook(id: notebook.id) }
    }

    func notebooksInFolderTree(_ id: UUID) -> [Notebook] {
        var ids: Set<UUID> = [id]
        var previousCount = 0
        while previousCount != ids.count {
            previousCount = ids.count
            for folder in folders where folder.parentID.map({ ids.contains($0) }) == true { ids.insert(folder.id) }
        }
        return notebooks.filter { $0.folderID.map { ids.contains($0) } == true }
    }
}
