import Foundation

/// Phase 1 only reads/writes small manifests. Move page and media IO to a dedicated
/// actor before phase 2; never perform heavy IO on the PencilKit delegate callback.
public struct NativeDocumentStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Recover an interrupted directory replacement before opening the library.
        for previous in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where previous.pathExtension == "cloudPrevious" {
            guard let id = UUID(uuidString: previous.deletingPathExtension().lastPathComponent) else { continue }
            let destination = root.appendingPathComponent("\(id).nnbook", isDirectory: true)
            guard let inspected = try? NativePackageInspector.inspect(previous), inspected.manifest.documentID == id else { continue }
            if FileManager.default.fileExists(atPath: destination.path) {
                if (try? NativePackageInspector.inspect(destination)) != nil { continue }
                // Retain a partially installed destination instead of allowing
                // it to hide the last complete snapshot after a crash.
                let retained = root.appendingPathComponent("\(id)-\(UUID()).cloudInterrupted", isDirectory: true)
                try FileManager.default.moveItem(at: destination, to: retained)
            }
            try FileManager.default.moveItem(at: previous, to: destination)
        }
    }

    public func packageURL(for documentID: UUID) -> URL {
        root.appendingPathComponent(documentID.uuidString, isDirectory: true)
            .appendingPathExtension("nnbook")
    }

    public func create(_ manifest: DocumentManifest, template: PageTemplate? = nil) throws {
        let destination = packageURL(for: manifest.documentID)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for name in ["pages", "drawings", "images", "audio", "attachments"] {
                try FileManager.default.createDirectory(
                    at: destination.appendingPathComponent(name, isDirectory: true),
                    withIntermediateDirectories: false)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let template {
                guard template.appearance.isValid else { throw LibraryFailure.corruptDocument }
                var catalog = DocumentCatalog(); catalog.defaultPageTemplate = template
                try encoder.encode(catalog).write(to: destination.appendingPathComponent("catalog.json"), options: .atomic)
            }
            try encoder.encode(manifest).write(
                to: destination.appendingPathComponent("manifest.json"), options: .atomic)
        } catch {
            let original = error
            do { try FileManager.default.removeItem(at: destination) }
            catch { throw LibraryFailure.recoveryRequired(original.localizedDescription) }
            throw original
        }
    }

    public func read(documentID: UUID, notebookID: UUID) throws -> DocumentManifest {
        let data = try Data(contentsOf: packageURL(for: documentID).appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Inspect the version before decoding the rest: a newer schema may change fields.
        struct Header: Decodable { let schemaVersion: Int }
        let version = try decoder.decode(Header.self, from: data).schemaVersion
        guard version == DocumentManifest.currentVersion else {
            throw LibraryFailure.unsupportedVersion(version)
        }
        let manifest = try decoder.decode(DocumentManifest.self, from: data)
        guard manifest.documentID == documentID, manifest.notebookID == notebookID,
              Set(manifest.pageIDs).count == manifest.pageIDs.count else {
            throw LibraryFailure.corruptDocument
        }
        return manifest
    }

    /// Only used when the database transaction failed, never for normal user deletion.
    public func removeUncommitted(documentID: UUID) throws {
        try FileManager.default.removeItem(at: packageURL(for: documentID))
    }

    /// Crash between file creation and DB commit: retain unreferenced packages in place.
    /// No automatic deletion or reset of an existing database is ever performed.
    public func unreferencedPackages(referencedDocumentIDs: Set<UUID>) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { url in
                guard url.pathExtension == "nnbook" else { return false }
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return true }
                return !referencedDocumentIDs.contains(id)
            }
    }
}
