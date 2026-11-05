import Foundation

extension NativeDocumentStore {
    public func restorePreviousManifest(documentID: UUID, notebookID: UUID) throws {
        let package = packageURL(for: documentID)
        let current = try NativeArchive.fileURL("manifest.json", in: package)
        let old = try NativeArchive.fileURL("manifest.previous.json", in: package)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        // Never roll an unknown format back. A supported v2 also establishes
        // a minimum even when the old recovery index was captured under v1.
        var minimumVersion = DocumentManifest.currentVersion
        if let bytes = try? Data(contentsOf: current), let object = try? JSONSerialization.jsonObject(with: bytes), let header = object as? [String: Any],
           let version = header["schemaVersion"] as? Int {
            guard DocumentManifest.supports(version) else { throw LibraryFailure.unsupportedVersion(version) }
            minimumVersion = max(minimumVersion, version)
        }
        guard (try old.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 << 20 else { throw NativeArchiveFailure.limit }
        let bytes = try Data(contentsOf: old)
        var manifest = try decoder.decode(DocumentManifest.self, from: bytes)
        guard DocumentManifest.supports(manifest.schemaVersion), manifest.documentID == documentID, manifest.notebookID == notebookID,
              Set(manifest.pageIDs).count == manifest.pageIDs.count else { throw LibraryFailure.corruptDocument }
        for id in manifest.pageIDs {
            let file = try NativeArchive.fileURL("pages/\(id).json", in: package)
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 << 20 else { throw NativeArchiveFailure.limit }
            let page = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: file))
            guard page.id == id else { throw LibraryFailure.corruptDocument }
            if page.layers != nil { minimumVersion = DocumentManifest.layersVersion }
        }
        // Recovery may remove pages from the live order, but their retained
        // headers still own ink. Scan only here, never during ordinary opening.
        let pages = try NativeArchive.fileURL("pages", in: package)
        if FileManager.default.fileExists(atPath: pages.path) {
            let files = try FileManager.default.contentsOfDirectory(at: pages, includingPropertiesForKeys: [.fileSizeKey])
            guard files.count <= 20_000 else { throw NativeArchiveFailure.limit }
            for file in files where file.pathExtension == "json" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
                let safe = try NativeArchive.fileURL("pages/\(file.lastPathComponent)", in: package)
                guard (try safe.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 << 20 else { throw NativeArchiveFailure.limit }
                if let data = try? Data(contentsOf: safe), let page = try? decoder.decode(PageSnapshot.self, from: data) {
                    if page.layers != nil { minimumVersion = DocumentManifest.layersVersion }
                } else { minimumVersion = DocumentManifest.layersVersion }
            }
        }
        manifest = manifest.retainingFormat(atLeast: minimumVersion)
        let recovery = try NativeArchive.fileURL("recovery", in: package)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: current.path) {
            try FileManager.default.copyItem(at: current, to: recovery.appendingPathComponent("manifest-\(UUID()).json"))
        }
        if manifest.schemaVersion >= DocumentManifest.layersVersion {
            _ = try NativePackageFormat.requiringLayers(in: package, manifest: manifest)
            // requiringLayers only writes the main index when promoting from
            // v1. This recovery intentionally restores a possibly older order.
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(to: current, options: .atomic)
        } else { try bytes.write(to: current, options: .atomic) }
    }
}
