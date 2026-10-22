import Foundation

public enum WorkspaceFailure: LocalizedError {
    case invalidPath, staleRevision, emptyDocument, oversizedImport, oversizedMetadata
    public var errorDescription: String? {
        switch self {
        case .invalidPath: return "Percorso del documento non valido."
        case .staleRevision: return "Il contenuto è stato modificato da un’altra sessione. Riapri il quaderno."
        case .emptyDocument: return "Aggiungi almeno una pagina."
        case .oversizedImport: return "File troppo grande per questa importazione (limite 100 MB)."
        case .oversizedMetadata: return "L’indice del quaderno supera 16 MB. L’ultima copia leggibile è stata conservata. Esporta un backup e continua in un nuovo quaderno."
        }
    }
}

/// Every mutation of a document passes through one serialized writer. Files are
/// committed before their references; a crash can leave unused files, never a half snapshot.
public actor DocumentWorkspace {
    public nonisolated let package: URL
    private let notebookID: UUID
    public nonisolated let documentID: UUID
    private var searchDirty = true
    private var searchChunks: [IndexedChunk] = []
    private var cachedCloudDigest: (metadata: String, digest: String)?
    public func cloudDigest(metadata: Notebook) throws -> String {
        let key = "\(metadata.title)|\(metadata.cover.rawValue)|\(metadata.isFavorite)"
        if let cachedCloudDigest, cachedCloudDigest.metadata == key { return cachedCloudDigest.digest }
        let digest = try SnapshotDigest.package(package, metadata: metadata)
        cachedCloudDigest = (key, digest); return digest
    }
    public func invalidateDerivedSearch() { searchDirty = true; searchChunks = []; ocrCache = nil; cachedCloudDigest = nil }
    private var ocrCache: [String: AutomaticOCRPage]?
    private var pageBatchSettled = false
    func markPendingPageBatch() { pageBatchSettled = false }
    func settlePageBatch() throws {
        guard !pageBatchSettled else { return }
        try PageBatchRecovery.recover(in: package); pageBatchSettled = true
    }
    private var ocrCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeuralNotesSearch").appendingPathComponent("\(documentID)-ocr.json")
    }
    private func loadOCRCache() -> [String: AutomaticOCRPage] {
        if let ocrCache { return ocrCache }
        let value = (try? Data(contentsOf: ocrCacheURL)).flatMap { try? JSONDecoder().decode([String: AutomaticOCRPage].self, from: $0) } ?? [:]
        ocrCache = value; return value
    }
    public func needsAutomaticOCR(pageID: UUID, revision: Int) -> Bool { loadOCRCache()[pageID.uuidString]?.revision != revision }
    @discardableResult
    public func storeAutomaticOCR(pageID: UUID, revision: Int, text: String) throws -> Bool {
        guard try readPage(pageID).revision == revision else { return false }
        var value = loadOCRCache()
        value[pageID.uuidString] = AutomaticOCRPage(revision: revision, text: String(text.prefix(20_000)))
        let live = Set(try manifest().pageIDs.map(\.uuidString)); value = value.filter { live.contains($0.key) }
        try FileManager.default.createDirectory(at: ocrCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: ocrCacheURL, options: .atomic)
        ocrCache = value; searchDirty = true; return true
    }

    public func indexedChunks() throws -> [IndexedChunk] {
        if !searchDirty { return searchChunks }
        let ids = try manifest().pageIDs
        let paths = ["manifest.json", "catalog.json"] + ids.map { "pages/\($0).json" }
        let generation = try (paths.map { path -> String in
            try Task.checkCancellation()
            let file = try url(path)
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(path):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
        } + ["ocr:\((try? ocrCacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0)"]).joined(separator: "|")
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeuralNotesSearch").appendingPathComponent("\(documentID).json")
        if let data = try? Data(contentsOf: cache), let snapshot = try? JSONDecoder().decode(SearchSnapshot.self, from: data),
           snapshot.format == 2, snapshot.generation == generation {
            searchChunks = snapshot.chunks
        } else {
            let ocr = loadOCRCache()
            let snapshot = SearchSnapshot.make(pages: try pages(), catalog: try catalog(), documentID: documentID, generation: generation, automaticOCR: ocr)
            searchChunks = snapshot.chunks
            // Derived-data failures never fail a notebook save or search.
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cache, options: .atomic) }
        }
        searchDirty = false; return searchChunks
    }

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
        try settlePageBatch()
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
    public func pageSnapshot(_ id: UUID) throws -> PageSnapshot {
        guard try manifest().pageIDs.contains(id) else { throw LibraryFailure.missingItem }
        return try readPage(id)
    }

    public func lastEditedPage() throws -> PageSnapshot? {
        try pages().filter { $0.lastEditedAt != nil }.max {
            ($0.lastEditedAt ?? 0) < ($1.lastEditedAt ?? 0)
        }
    }

    public func drawing(_ page: PageSnapshot) throws -> Data? {
        guard let file = page.drawingFile else { return nil }
        return try Data(contentsOf: url(file))
    }

    public func addPage(_ input: PageSnapshot = PageSnapshot()) throws -> PageSnapshot {
        try PageValidation.validate(input)
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

    /// Publish a PDF's pages with one manifest commit. Validation happens before
    /// any write; interrupted preparation cannot expose a partially imported PDF.
    public func appendPages(_ inputs: [PageSnapshot]) throws -> [PageSnapshot] {
        guard !inputs.isEmpty, inputs.count <= 1000 else { throw LibraryFailure.corruptDocument }
        var index = try manifest()
        var ids = Set(index.pageIDs)
        for page in inputs {
            try PageValidation.validate(page)
            guard page.appearance?.isValid != false, ids.insert(page.id).inserted,
                  !FileManager.default.fileExists(atPath: try url("pages/\(page.id).json").path) else { throw LibraryFailure.corruptDocument }
        }
        for page in inputs {
            try Task.checkCancellation()
            try write(page, "pages/\(page.id).json")
        }
        try Task.checkCancellation()
        index.pageIDs.append(contentsOf: inputs.map(\.id))
        try write(index, "manifest.json")
        return inputs
    }

    public func setDefaultPageTemplate(_ template: PageTemplate) throws {
        guard template.appearance.isValid else { throw LibraryFailure.corruptDocument }
        if let file = template.pdfFile {
            guard let index = template.pdfIndex, index >= 0, index < Int.max, let width = template.sourceWidth, let height = template.sourceHeight,
                  width.isFinite, height.isFinite, (1...20000).contains(width), (1...20000).contains(height),
                  FileManager.default.fileExists(atPath: try url(file).path) else { throw LibraryFailure.corruptDocument }
        }
        var value = try catalog(); value.defaultPageTemplate = template
        try write(value, "catalog.json")
    }

    public func addDefaultPage() throws -> PageSnapshot {
        let template = try catalog().defaultPageTemplate ?? PageTemplate()
        return try addPage(template.makePage())
    }

    public func save(_ input: PageSnapshot, drawing: Data, recoveredFromPrevious: Bool = false) throws -> PageSnapshot {
        // Keep newly written files within the same limits as backup/import.
        // Otherwise a successful save could create an unexportable notebook.
        guard drawing.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        try PageValidation.validate(input)
        guard input.appearance?.isValid != false else { throw LibraryFailure.corruptDocument }
        let current = try readPage(input.id)
        guard input.revision > current.revision else { throw WorkspaceFailure.staleRevision }
        var page = input
        page.lastEditedAt = Date().timeIntervalSince1970
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
        copy.lastEditedAt = Date().timeIntervalSince1970
        copy.renewObjectIDs()
        for index in copy.anchors.indices { copy.anchors[index].id = UUID() }
        if let file = original.drawingFile {
            let newFile = "drawings/\(copy.id)-\(UUID()).drawing"
            try FileManager.default.copyItem(at: url(file), to: url(newFile))
            copy.drawingFile = newFile
        }
        return try addPage(copy)
    }

    public func deletePage(_ pageID: UUID) throws {
        try deletePages([pageID])
    }

    public func deletePages(_ ids: Set<UUID>) throws {
        var index = try manifest()
        guard !ids.isEmpty, ids.isSubset(of: Set(index.pageIDs)) else { throw LibraryFailure.missingItem }
        index.pageIDs.removeAll { ids.contains($0) }
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
        page.lastEditedAt = Date().timeIntervalSince1970
        try write(page, "pages/\(id).json")
        return page
    }

    public func catalog() throws -> DocumentCatalog {
        let file = try url("catalog.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            if FileManager.default.fileExists(atPath: try url(CatalogRecovery.previousPath).path) {
                throw LibraryFailure.recoveryRequired("Catalogo mancante: apri Recupero quaderni dalla libreria.")
            }
            return DocumentCatalog()
        }
        return try CatalogRecovery.read("catalog.json", package: package)
    }

    public func setEditorWorkspaces(_ settings: NotebookWorkspaces) throws {
        guard settings.isValid else { throw LibraryFailure.corruptDocument }
        var index = try catalog(); index.editorWorkspaces = settings
        try write(index, "catalog.json")
    }

    public func setCoverAppearance(image: Data?, design: CoverDesign, useLastEditedPage: Bool? = nil) throws {
        guard design.isValid else { throw LibraryFailure.corruptDocument }
        var index = try catalog(); index.coverImageFile = try image.map { try storeImage($0) }; index.coverDesign = design
        if let useLastEditedPage { index.coverUsesLastEditedPage = useLastEditedPage }
        try write(index, "catalog.json")
    }

    public func saveSession(_ session: AudioSession) throws {
        guard (0...1_000_000_000).contains(session.revision ?? 0) else { throw LibraryFailure.corruptDocument }
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
        guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
        let file = "images/\(UUID()).png"
        try data.write(to: url(file), options: .atomic)
        return file
    }

    public func saveArtifact(_ artifact: AIArtifact) throws {
        let directory = try url("artifacts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(artifact, "artifacts/\(artifact.id).json")
    }
    public func saveConversationTurn(_ turn: AIConversationTurn) throws {
        guard turn.question.count <= 4000, turn.answer.text.count <= 100_000 else { throw WorkspaceFailure.oversizedImport }
        var value = try catalog()
        value.conversation = Array(((value.conversation ?? []) + [turn]).suffix(20))
        try write(value, "catalog.json")
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
        try settlePageBatch()
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else {
            throw LibraryFailure.recoveryRequired("Metti in pausa o termina la registrazione prima di duplicare il quaderno.")
        }
        try store.clone(from: package, documentID: documentID, notebookID: notebookID)
    }

    public func exportNative(metadata: Notebook) throws -> URL {
        try settlePageBatch()
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
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else { throw LibraryFailure.corruptDocument }
        var index = try catalog()
        guard var cards = index.studyCards, let position = cards.firstIndex(where: { $0.id == id }) else { throw LibraryFailure.missingItem }
        if index.adaptiveReview == true { try cards[position].reviewAdaptive(rating, now: now) }
        else { cards[position].review(rating, now: now) }
        index.studyCards = cards
        let event = StudyReviewEvent(cardID: id, rating: rating, date: now, intervalDays: cards[position].intervalDays)
        guard event.isValid else { throw LibraryFailure.corruptDocument }
        index.reviewLog = Array(((index.reviewLog ?? []) + [event]).suffix(10_000))
        try write(index, "catalog.json")
    }
    public func setAdaptiveReview(_ enabled: Bool) throws {
        var index = try catalog(); guard index.adaptiveReview != enabled else { return }
        index.adaptiveReview = enabled; try write(index, "catalog.json")
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
        try Task.checkCancellation()
        try settlePageBatch()
        let page: PageSnapshot = try read("pages/\(id).json")
        try PageValidation.validate(page)
        guard page.id == id, page.width.isFinite, page.height.isFinite,
              page.width > 0, page.height > 0, page.width <= 20000, page.height <= 20000 else {
            throw LibraryFailure.corruptDocument
        }
        for path in [page.drawingFile, page.previousDrawingFile, page.pdfFile].compactMap({ $0 }) + page.images.map(\.file) {
            _ = try url(path)
        }
        if let appearance = page.appearance, !appearance.isValid { throw LibraryFailure.corruptDocument }
        if let time = page.lastEditedAt, !time.isFinite || time < 0 { throw LibraryFailure.corruptDocument }
        return page
    }

    private func read<T: Decodable>(_ path: String) throws -> T {
        let file = try url(path)
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw NativeArchiveFailure.limit }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: file))
    }

    func write<T: Encodable>(_ value: T, _ path: String) throws {
        if let page = value as? PageSnapshot { try PageValidation.validate(page) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        if path.hasSuffix(".json"), data.count > 16 * 1024 * 1024 { throw WorkspaceFailure.oversizedMetadata }
        searchDirty = true
        cachedCloudDigest = nil
        if path == "catalog.json" { try CatalogRecovery.preserveCurrent(in: package) }
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
