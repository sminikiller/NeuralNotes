import Foundation

public enum WorkspaceFailure: LocalizedError {
    case invalidPath, staleRevision, emptyDocument, oversizedImport
    public var errorDescription: String? {
        switch self {
        case .invalidPath: return "Percorso del documento non valido."
        case .staleRevision: return "Il contenuto è stato modificato da un’altra sessione. Riapri il quaderno."
        case .emptyDocument: return "Aggiungi almeno una pagina."
        case .oversizedImport: return "File troppo grande per questa importazione (limite 100 MB)."
        }
    }
}

/// Every mutation of a document passes through one serialized writer. Files are
/// committed before their references; a crash can leave unused files, never a half snapshot.
public actor DocumentWorkspace {
    public nonisolated let package: URL
    private let notebookID: UUID
    public nonisolated let documentID: UUID

    public init(package: URL, documentID: UUID, notebookID: UUID) {
        self.package = package; self.documentID = documentID; self.notebookID = notebookID
    }

    public func url(_ relative: String) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard package.isFileURL, !components.isEmpty, !relative.contains("\\"), !relative.contains(":"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw WorkspaceFailure.invalidPath
        }
        // Resolve the existing package once, not the entire (possibly nonexistent)
        // destination. Darwin may normalize /private/var differently for existing
        // and new paths. A directory URL can also preserve a trailing slash.
        var result = package.standardizedFileURL.resolvingSymlinksInPath()
        for component in components {
            result = result.appendingPathComponent(String(component), isDirectory: false)
            // Generated packages need no symlinks below their root. Reject even
            // dangling links, before a reader/writer could follow one outside.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: result.path)) != nil {
                throw WorkspaceFailure.invalidPath
            }
        }
        return result
    }

    public func manifest() throws -> DocumentManifest {
        let value: DocumentManifest = try read("manifest.json")
        guard value.schemaVersion == 1, value.documentID == documentID,
              value.notebookID == notebookID, Set(value.pageIDs).count == value.pageIDs.count else {
            throw LibraryFailure.corruptDocument
        }
        return value
    }

    public func pages() throws -> [PageSnapshot] {
        try manifest().pageIDs.map { try readPage($0) }
    }

    public func drawing(_ page: PageSnapshot) throws -> Data? {
        guard let file = page.drawingFile else { return nil }
        return try Data(contentsOf: url(file))
    }

    public func addPage(_ input: PageSnapshot = PageSnapshot()) throws -> PageSnapshot {
        guard input.appearance?.isValid != false else { throw LibraryFailure.corruptDocument }
        var index = try manifest()
        guard !index.pageIDs.contains(input.id), input.width.isFinite, input.height.isFinite,
              input.width > 0, input.height > 0, input.width <= 20000, input.height <= 20000 else {
            throw LibraryFailure.corruptDocument
        }
        try write(input, "pages/\(input.id).json")
        index.pageIDs.append(input.id)
        try write(index, "manifest.json")
        return input
    }

    public func setDefaultPageTemplate(_ template: PageTemplate) throws {
        guard template.appearance.isValid else { throw LibraryFailure.corruptDocument }
        var value = try catalog(); value.defaultPageTemplate = template
        try write(value, "catalog.json")
    }

    public func addDefaultPage() throws -> PageSnapshot {
        let template = try catalog().defaultPageTemplate ?? PageTemplate()
        return try addPage(template.makePage())
    }

    public func save(_ input: PageSnapshot, drawing: Data, recoveredFromPrevious: Bool = false) throws -> PageSnapshot {
        guard input.appearance?.isValid != false else { throw LibraryFailure.corruptDocument }
        let current = try readPage(input.id)
        guard input.revision > current.revision else { throw WorkspaceFailure.staleRevision }
        var page = input
        let newFile = "drawings/\(page.id)-\(UUID()).drawing"
        try drawing.write(to: url(newFile), options: .atomic)
        page.drawingFile = newFile
        page.previousDrawingFile = recoveredFromPrevious ? current.previousDrawingFile : current.drawingFile
        try write(page, "pages/\(page.id).json")
        // At most two vector snapshots per page; never remove either committed reference.
        if let old = current.previousDrawingFile, old != page.previousDrawingFile,
           old != newFile, old.hasPrefix("drawings/\(page.id)-") {
            try? FileManager.default.removeItem(at: url(old))
        }
        return page
    }

    public func duplicatePage(_ pageID: UUID) throws -> PageSnapshot {
        let original = try readPage(pageID)
        var copy = original
        copy.id = UUID(); copy.revision = 0; copy.previousDrawingFile = nil
        for index in copy.texts.indices { copy.texts[index].id = UUID() }
        for index in copy.images.indices { copy.images[index].id = UUID() }
        if var shapes = copy.shapes {
            for index in shapes.indices { shapes[index].id = UUID() }; copy.shapes = shapes
        }
        for index in copy.anchors.indices { copy.anchors[index].id = UUID() }
        if let file = original.drawingFile {
            let newFile = "drawings/\(copy.id)-\(UUID()).drawing"
            try FileManager.default.copyItem(at: url(file), to: url(newFile))
            copy.drawingFile = newFile
        }
        return try addPage(copy)
    }

    public func deletePage(_ pageID: UUID) throws {
        var index = try manifest()
        index.pageIDs.removeAll { $0 == pageID }
        // Files retained for recovery; removal from the ordered manifest is the commit.
        try write(index, "manifest.json")
    }

    public func movePage(_ pageID: UUID, offset: Int) throws {
        var index = try manifest()
        guard let from = index.pageIDs.firstIndex(of: pageID) else { throw LibraryFailure.missingItem }
        let to = min(max(from + offset, 0), index.pageIDs.count - 1)
        index.pageIDs.remove(at: from); index.pageIDs.insert(pageID, at: to)
        try write(index, "manifest.json")
    }

    public func reorderPages(_ ids: [UUID]) throws {
        var index = try manifest()
        guard ids.count == index.pageIDs.count, Set(ids) == Set(index.pageIDs) else { throw LibraryFailure.corruptDocument }
        index.pageIDs = ids
        try write(index, "manifest.json")
    }

    public func restorePageOrder(_ ids: [UUID], expected: [UUID]) throws {
        var index = try manifest()
        guard index.pageIDs == expected else { throw WorkspaceFailure.staleRevision }
        guard Set(ids).count == ids.count, !ids.isEmpty else { throw LibraryFailure.corruptDocument }
        for id in ids { _ = try readPage(id) }
        index.pageIDs = ids
        try write(index, "manifest.json")
    }

    public func setPageDetails(_ id: UUID, title: String?, bookmarked: Bool) throws -> PageSnapshot {
        var page = try readPage(id)
        page.title = try title.map { try LibraryName.validated($0) }
        page.isBookmarked = bookmarked; page.revision += 1
        try write(page, "pages/\(id).json")
        return page
    }

    public func catalog() throws -> DocumentCatalog {
        let file = try url("catalog.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return DocumentCatalog() }
        let result: DocumentCatalog = try read("catalog.json")
        guard result.schemaVersion == 1 else { throw LibraryFailure.unsupportedVersion(result.schemaVersion) }
        if let template = result.defaultPageTemplate, !template.appearance.isValid { throw LibraryFailure.corruptDocument }
        if let settings = result.editorWorkspaces, !settings.isValid { throw LibraryFailure.corruptDocument }
        if let design = result.coverDesign, !design.isValid { throw LibraryFailure.corruptDocument }
        return result
    }

    public func setEditorWorkspaces(_ settings: NotebookWorkspaces) throws {
        guard settings.isValid else { throw LibraryFailure.corruptDocument }
        var index = try catalog(); index.editorWorkspaces = settings
        try write(index, "catalog.json")
    }

    public func setCoverAppearance(image: Data?, design: CoverDesign) throws {
        guard design.isValid else { throw LibraryFailure.corruptDocument }
        var index = try catalog(); index.coverImageFile = try image.map { try storeImage($0) }; index.coverDesign = design
        try write(index, "catalog.json")
    }

    public func saveSession(_ session: AudioSession) throws {
        var index = try catalog()
        if let current = index.sessions.first(where: { $0.id == session.id }) {
            if (current.revision ?? 0) > (session.revision ?? 0) { return }
            if (current.revision ?? 0) == (session.revision ?? 0), current != session {
                throw WorkspaceFailure.staleRevision
            }
        }
        index.sessions.removeAll { $0.id == session.id }
        index.sessions.append(session)
        try write(index, "catalog.json")
    }

    public func addAttachment(_ data: Data, name: String, type: String, hash: String) throws -> Attachment {
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        let item = Attachment(file: "attachments/\(UUID()).\(type == "pdf" ? "pdf" : "bin")",
                              originalName: name, type: type, sha256: hash)
        try data.write(to: url(item.file), options: .atomic)
        var index = try catalog(); index.attachments.append(item)
        try write(index, "catalog.json")
        return item
    }

    public func storeImage(_ data: Data) throws -> String {
        let file = "images/\(UUID()).png"
        try data.write(to: url(file), options: .atomic)
        return file
    }

    public func saveArtifact(_ artifact: AIArtifact) throws {
        let directory = try url("artifacts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(artifact, "artifacts/\(artifact.id).json")
    }

    public func artifacts() throws -> [AIArtifact] {
        let directory = try url("artifacts")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try files.map { try decoder.decode(AIArtifact.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func clone(to store: NativeDocumentStore, documentID: UUID, notebookID: UUID) throws {
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else {
            throw LibraryFailure.recoveryRequired("Metti in pausa o termina la registrazione prima di duplicare il quaderno.")
        }
        try store.clone(from: package, documentID: documentID, notebookID: notebookID)
    }

    public func exportNative(metadata: Notebook) throws -> URL {
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else {
            throw LibraryFailure.recoveryRequired("Metti in pausa la registrazione prima di esportare il backup.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("NeuralNotes.nnbackup", isDirectory: false)
        try NativeArchive.write(package: package, metadata: metadata, to: destination)
        return destination
    }

    public func setCoverImage(_ data: Data?) throws {
        var value = try catalog()
        value.coverImageFile = try data.map { try storeImage($0) }
        try write(value, "catalog.json")
    }

    public func addStudyCards(_ cards: [StudyCard]) throws {
        var index = try catalog()
        var stored = index.studyCards ?? []
        for card in cards where !stored.contains(where: { $0.question == card.question && $0.source == card.source }) {
            stored.append(card)
        }
        index.studyCards = stored
        try write(index, "catalog.json")
    }

    public func reviewCard(_ id: UUID, rating: ReviewRating, now: Date = Date()) throws {
        var index = try catalog()
        guard var cards = index.studyCards, let position = cards.firstIndex(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        cards[position].review(rating, now: now); index.studyCards = cards
        try write(index, "catalog.json")
    }

    public func removeStudyCard(_ id: UUID) throws {
        var index = try catalog(); index.studyCards?.removeAll { $0.id == id }
        try write(index, "catalog.json")
    }

    public func search(_ query: String) throws -> [(UUID, String)] {
        try pages().compactMap { page in
            let text = (page.texts.map(\.text) + [page.recognizedText]).joined(separator: "\n")
            return text.localizedStandardContains(query) ? (page.id, text) : nil
        }
    }

    private func readPage(_ id: UUID) throws -> PageSnapshot {
        let page: PageSnapshot = try read("pages/\(id).json")
        guard page.id == id, page.width.isFinite, page.height.isFinite,
              page.width > 0, page.height > 0, page.width <= 20000, page.height <= 20000 else {
            throw LibraryFailure.corruptDocument
        }
        for path in [page.drawingFile, page.previousDrawingFile, page.pdfFile].compactMap({ $0 }) + page.images.map(\.file) {
            _ = try url(path)
        }
        if let appearance = page.appearance, !appearance.isValid { throw LibraryFailure.corruptDocument }
        return page
    }

    private func read<T: Decodable>(_ path: String) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url(path)))
    }

    func write<T: Encodable>(_ value: T, _ path: String) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        if path == "manifest.json" {
            let current = try url(path)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            if let previous = try? Data(contentsOf: current),
               let manifest = try? decoder.decode(DocumentManifest.self, from: previous),
               manifest.schemaVersion == 1, manifest.documentID == documentID, manifest.notebookID == notebookID {
                try previous.write(to: url("manifest.previous.json"), options: .atomic)
            }
        }
        try data.write(to: url(path), options: .atomic)
    }
}
