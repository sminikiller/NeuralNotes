import Foundation

public enum NotebookCover: String, Codable, CaseIterable, Sendable {
    case midnight, lagoon, terracotta, lavender, sand

    public var title: String {
        switch self {
        case .midnight: return "Notte"
        case .lagoon: return "Laguna"
        case .terracotta: return "Terracotta"
        case .lavender: return "Lavanda"
        case .sand: return "Sabbia"
        }
    }
}

public struct Notebook: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let documentID: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let folderID: UUID?
    public let cover: NotebookCover
    public let isFavorite: Bool

    public init(id: UUID, documentID: UUID, title: String, createdAt: Date,
                updatedAt: Date, folderID: UUID?, cover: NotebookCover, isFavorite: Bool) {
        self.id = id
        self.documentID = documentID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.cover = cover
        self.isFavorite = isFavorite
    }
}

public struct LibraryFolder: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let parentID: UUID?

    public init(id: UUID, title: String, parentID: UUID?) {
        self.id = id
        self.title = title
        self.parentID = parentID
    }
}

public enum LibraryFailure: LocalizedError {
    case invalidName
    case missingItem
    case nonEmptyFolder
    case corruptDocument
    case unsupportedVersion(Int)
    case duplicationRequiresEditor
    case recoveryRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Inserisci un nome da 1 a 120 caratteri, su una sola riga."
        case .missingItem: return "L’elemento non è più disponibile. Aggiorna la libreria."
        case .nonEmptyFolder: return "Sposta o elimina prima i quaderni e le sottocartelle."
        case .corruptDocument: return "Il documento è incompleto o danneggiato. I file originali sono stati conservati."
        case .unsupportedVersion(let version): return "Questo documento usa il formato v\(version), non supportato da questa versione dell’app."
        case .duplicationRequiresEditor: return "Questa versione può duplicare soltanto i quaderni vuoti. Le pagine originali sono state conservate."
        case .recoveryRequired(let details): return "Operazione interrotta. I file sono stati conservati per il recupero. \(details)"
        }
    }
}

public enum LibraryName {
    public static func validated(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120,
              name.rangeOfCharacter(from: .newlines) == nil else {
            throw LibraryFailure.invalidName
        }
        return name
    }
}

/// The UI depends on value snapshots, never on live SwiftData model objects.
@MainActor
public protocol LibraryRepository: AnyObject {
    func notebooks() throws -> [Notebook]
    func trashedNotebooks() throws -> [Notebook]
    func folders() throws -> [LibraryFolder]
    func createNotebook(title: String, folderID: UUID?, cover: NotebookCover, template: PageTemplate?) throws -> Notebook
    func updateNotebook(id: UUID, title: String, folderID: UUID?, cover: NotebookCover) throws
    func setFavorite(id: UUID, isFavorite: Bool) throws
    func duplicateNotebook(id: UUID) async throws -> Notebook
    func importNotebook(from url: URL, folderID: UUID?) async throws -> Notebook
    func deleteNotebook(id: UUID) throws
    func restoreNotebook(id: UUID) throws
    func createFolder(title: String, parentID: UUID?) throws
    func renameFolder(id: UUID, title: String) throws
    func deleteFolder(id: UUID) throws
    func openNotebook(id: UUID) throws -> DocumentManifest
    func workspace(id: UUID) throws -> DocumentWorkspace
    func recoverablePackages() throws -> [URL]
    func recoverPackage(_ url: URL) async throws
    func repairNotebookIndex(id: UUID) throws
    func touchNotebook(id: UUID) throws
}
