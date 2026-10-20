import Foundation

public enum NativeImport {
    /// Call off the UI actor; the scope of an external file must remain open until
    /// this finishes. New identities protect an already-open original notebook.
    public static func copy(from source: URL, into store: NativeDocumentStore,
                            documentID: UUID, notebookID: UUID) throws -> Notebook? {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NN-import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let package: URL
        if isDirectory { package = source }
        else {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            package = temporary.appendingPathComponent("Imported.nnbook", isDirectory: true)
            try NativeArchive.extract(from: source, to: package)
        }
        let inspected = try NativePackageInspector.inspect(package)
        try Task.checkCancellation()
        try store.clone(from: package, documentID: documentID, notebookID: notebookID)
        return inspected.metadata
    }
}
