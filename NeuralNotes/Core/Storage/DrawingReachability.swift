import Foundation

/// Derived metadata only, built lazily before the first obsolete vector file
/// is released. It includes trashed pages and hidden/locked layers. No drawing
/// payload, PDF, image or recording is loaded. Every serialized header write
/// updates the counts; journal recovery invalidates the derived index.
struct DrawingReachability {
    private var pages: [UUID: Set<String>] = [:]
    private var counts: [String: Int] = [:]
    mutating func replace(_ page: PageSnapshot) {
        let next = Set(page.allDrawingFiles), previous = pages[page.id] ?? []
        for path in previous.subtracting(next) {
            let remaining = (counts[path] ?? 1) - 1
            if remaining == 0 { counts.removeValue(forKey: path) } else { counts[path] = remaining }
        }
        for path in next.subtracting(previous) { counts[path, default: 0] += 1 }
        pages[page.id] = next
    }
    func contains(_ path: String) -> Bool { (counts[path] ?? 0) > 0 }
}

extension DocumentWorkspace {
    func invalidateDrawingReachability() {
        drawingReachability = nil; drawingReferenceScanFailed = false
    }
    func canReleaseDrawing(_ path: String) -> Bool {
        guard !drawingReferenceScanFailed else { return false }
        if drawingReachability == nil {
            do {
                let directory = try url("pages")
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                // Corrupt or excessive metadata never authorizes deletion. The
                // normal save still commits, and maintenance reports recovery.
                guard files.count <= 20_000 else { drawingReferenceScanFailed = true; return false }
                var index = DrawingReachability()
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                for file in files {
                    try Task.checkCancellation()
                    let validated = try url("pages/\(file.lastPathComponent)")
                    let info = try validated.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard info.isRegularFile == true, let size = info.fileSize, size <= 16 * 1024 * 1024 else { throw LibraryFailure.corruptDocument }
                    let page = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: validated))
                    guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) == page.id else { throw LibraryFailure.corruptDocument }
                    try PageValidation.validate(page)
                    index.replace(page)
                }
                drawingReachability = index
            } catch { drawingReferenceScanFailed = true; return false }
        }
        return drawingReachability?.contains(path) == false
    }
}
