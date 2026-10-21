import Foundation

/// Own copied media independently of the source notebook. Cutting an image,
/// closing the source and cleaning its unused files must not empty the clipboard.
public final class SelectionSnapshot: Sendable {
    public let page: PageSnapshot
    public let drawing: Data?
    public let package: URL
    private let ownsPackage: Bool
    public init(page: PageSnapshot, drawing: Data?, source: URL, maximumBytes: Int) throws {
        let metadataSize = try JSONEncoder().encode(page).count
        guard maximumBytes >= 0, metadataSize <= maximumBytes, (drawing?.count ?? 0) <= maximumBytes - metadataSize else { throw WorkspaceFailure.oversizedImport }
        var remaining = maximumBytes - metadataSize - (drawing?.count ?? 0)
        let files = Set(page.images.map(\.file)).sorted()
        for path in files {
            let file = try NativeArchive.fileURL(path, in: source)
            let info = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard info.isRegularFile == true, let size = info.fileSize, size >= 0, size <= remaining else { throw WorkspaceFailure.oversizedImport }
            remaining -= size
        }
        let owned = files.isEmpty ? nil : FileManager.default.temporaryDirectory.appendingPathComponent("NN-clipboard-\(UUID())", isDirectory: true)
        var completed = false
        defer { if !completed, let owned { try? FileManager.default.removeItem(at: owned) } }
        var copy = page
        if let owned {
            try FileManager.default.createDirectory(at: owned.appendingPathComponent("images"), withIntermediateDirectories: true)
            var mapping: [String: String] = [:]
            for path in files {
                let destination = "images/\(UUID()).png"
                try FileManager.default.copyItem(at: NativeArchive.fileURL(path, in: source), to: owned.appendingPathComponent(destination))
                mapping[path] = destination
            }
            for i in copy.images.indices { copy.images[i].file = mapping[copy.images[i].file]! }
        }
        self.page = copy; self.drawing = drawing; package = owned ?? source; ownsPackage = owned != nil; completed = true
    }
    deinit { if ownsPackage { try? FileManager.default.removeItem(at: package) } }
}

