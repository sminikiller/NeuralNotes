import Foundation

/// Old readers reject manifest v2 before they can ignore the optional layer
/// fields and delete their media as unused. Legacy notebooks remain v1 until
/// their first explicit layer header is about to be committed. No page/ink
/// migration or media decode is needed for this monotonic format fence.
enum NativePackageFormat {
    static func requiringLayers(in package: URL, manifest: DocumentManifest) throws -> DocumentManifest {
        guard DocumentManifest.supports(manifest.schemaVersion) else { throw LibraryFailure.unsupportedVersion(manifest.schemaVersion) }
        let upgraded = manifest.retainingFormat(atLeast: DocumentManifest.layersVersion)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(upgraded)
        // This second atomic write completes before any layer header. A crash
        // between the two manifest writes still has only legacy page contents.
        let backup = try NativeArchive.fileURL("manifest.previous.json", in: package)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var protected = false
        if FileManager.default.fileExists(atPath: backup.path) {
            let info = try backup.resourceValues(forKeys: [.fileSizeKey])
            guard let size = info.fileSize, size <= 16 << 20 else { throw NativeArchiveFailure.limit }
            if let data = try? Data(contentsOf: backup) {
                struct Header: Decodable { let schemaVersion: Int }
                if let version = try? decoder.decode(Header.self, from: data).schemaVersion,
                   !DocumentManifest.supports(version) { throw LibraryFailure.unsupportedVersion(version) }
                if let previous = try? decoder.decode(DocumentManifest.self, from: data) {
                    protected = previous.schemaVersion == DocumentManifest.layersVersion && previous.documentID == manifest.documentID && previous.notebookID == manifest.notebookID
                }
            }
        }
        if manifest.schemaVersion < upgraded.schemaVersion {
            try bytes.write(to: NativeArchive.fileURL("manifest.json", in: package), options: .atomic)
        }
        if !protected { try bytes.write(to: backup, options: .atomic) }
        return upgraded
    }
}
