import Foundation

extension NativeDocumentStore {
    public func restorePreviousManifest(documentID: UUID, notebookID: UUID) throws {
        let package = packageURL(for: documentID)
        let current = try NativeArchive.fileURL("manifest.json", in: package)
        let old = try NativeArchive.fileURL("manifest.previous.json", in: package)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        // Never roll a newer supported-by-someone-else format back to v1.
        if let bytes = try? Data(contentsOf: current), let object = try? JSONSerialization.jsonObject(with: bytes), let header = object as? [String: Any],
           let version = header["schemaVersion"] as? Int, version != 1 { throw LibraryFailure.unsupportedVersion(version) }
        let bytes = try Data(contentsOf: old)
        let manifest = try decoder.decode(DocumentManifest.self, from: bytes)
        guard manifest.schemaVersion == 1, manifest.documentID == documentID, manifest.notebookID == notebookID,
              Set(manifest.pageIDs).count == manifest.pageIDs.count else { throw LibraryFailure.corruptDocument }
        for id in manifest.pageIDs {
            let file = try NativeArchive.fileURL("pages/\(id).json", in: package)
            let page = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: file))
            guard page.id == id else { throw LibraryFailure.corruptDocument }
        }
        let recovery = try NativeArchive.fileURL("recovery", in: package)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: current.path) {
            try FileManager.default.copyItem(at: current, to: recovery.appendingPathComponent("manifest-\(UUID()).json"))
        }
        try bytes.write(to: current, options: .atomic)
    }
}
