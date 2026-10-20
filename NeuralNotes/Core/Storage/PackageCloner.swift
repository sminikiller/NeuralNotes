import Foundation

extension NativeDocumentStore {
    /// A document copy gets fresh entity identities. Media names are package scoped
    /// and may be reused verbatim; no source file is ever changed.
    public func clone(from source: URL, documentID: UUID, notebookID: UUID) throws {
        let destination = packageURL(for: documentID)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let manifest = try decoder.decode(DocumentManifest.self,
            from: Data(contentsOf: source.appendingPathComponent("manifest.json")))
        guard manifest.schemaVersion == 1, Set(manifest.pageIDs).count == manifest.pageIDs.count else {
            throw LibraryFailure.corruptDocument
        }
        guard let enumerator = FileManager.default.enumerator(at: source,
            includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { throw LibraryFailure.corruptDocument }
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw WorkspaceFailure.invalidPath
            }
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            var catalog = DocumentCatalog()
            let catalogURL = destination.appendingPathComponent("catalog.json")
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                catalog = try decoder.decode(DocumentCatalog.self, from: Data(contentsOf: catalogURL))
            }
            var sessionMap: [UUID: UUID] = [:]
            for index in catalog.sessions.indices {
                let id = UUID(); sessionMap[catalog.sessions[index].id] = id
                catalog.sessions[index].id = id
                if catalog.sessions[index].state == "recording" { catalog.sessions[index].state = "paused" }
                for segment in catalog.sessions[index].segments.indices { catalog.sessions[index].segments[segment].id = UUID() }
                for segment in catalog.sessions[index].transcript.indices { catalog.sessions[index].transcript[segment].id = UUID() }
                if var chunks = catalog.sessions[index].transcriptionChunks {
                    for chunk in chunks.indices {
                        for word in chunks[chunk].segments.indices { chunks[chunk].segments[word].id = UUID() }
                    }
                    catalog.sessions[index].transcriptionChunks = chunks
                }
            }
            for index in catalog.attachments.indices { catalog.attachments[index].id = UUID() }
            try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
            var pageIDs: [UUID] = []
            var pageMap: [UUID: UUID] = [:]
            for original in manifest.pageIDs {
                let oldURL = destination.appendingPathComponent("pages/\(original).json")
                var page = try decoder.decode(PageSnapshot.self, from: Data(contentsOf: oldURL))
                guard page.id == original else { throw LibraryFailure.corruptDocument }
                page.id = UUID()
                pageMap[original] = page.id
                for index in page.texts.indices { page.texts[index].id = UUID() }
                for index in page.images.indices { page.images[index].id = UUID() }
                if var shapes = page.shapes {
                    for index in shapes.indices { shapes[index].id = UUID() }; page.shapes = shapes
                }
                for index in page.anchors.indices {
                    page.anchors[index].id = UUID()
                    if let mapped = sessionMap[page.anchors[index].audioSessionID] { page.anchors[index].audioSessionID = mapped }
                }
                try encoder.encode(page).write(to: destination.appendingPathComponent("pages/\(page.id).json"), options: .atomic)
                pageIDs.append(page.id)
                try FileManager.default.removeItem(at: oldURL)
            }
            let updated = DocumentManifest(documentID: documentID, notebookID: notebookID, pageIDs: pageIDs)
            try encoder.encode(updated).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
            // A source backup references source page IDs. Seed a valid recovery
            // index for the copied identity instead of retaining that old index.
            try encoder.encode(updated).write(to: destination.appendingPathComponent("manifest.previous.json"), options: .atomic)
            if var cards = catalog.studyCards {
                for index in cards.indices {
                    cards[index].id = UUID()
                    let ref = cards[index].source
                    if ref.documentID == manifest.documentID {
                        cards[index].source = SourceReference(documentID: documentID, pageID: ref.pageID.flatMap { pageMap[$0] },
                            audioSessionID: ref.audioSessionID.flatMap { sessionMap[$0] }, seconds: ref.seconds, pageRevision: ref.pageRevision)
                    }
                }
                catalog.studyCards = cards
                try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
            }
            // Artifacts belong to the copied document too; remap only local sources.
            let artifacts = destination.appendingPathComponent("artifacts")
            if FileManager.default.fileExists(atPath: artifacts.path) {
                for file in try FileManager.default.contentsOfDirectory(at: artifacts, includingPropertiesForKeys: nil)
                    where file.pathExtension == "json" {
                    let original = try decoder.decode(AIArtifact.self, from: Data(contentsOf: file))
                    let references = original.references.map { reference -> SourceReference in
                        guard reference.documentID == manifest.documentID else { return reference }
                        return SourceReference(documentID: documentID, pageID: reference.pageID.flatMap { pageMap[$0] },
                            audioSessionID: reference.audioSessionID.flatMap { sessionMap[$0] }, seconds: reference.seconds,
                            pageRevision: reference.pageRevision)
                    }
                    let copy = AIArtifact(text: original.text, references: references, provider: original.provider,
                        createdAt: original.createdAt, task: original.task)
                    try encoder.encode(copy).write(to: artifacts.appendingPathComponent("\(copy.id).json"), options: .atomic)
                    try FileManager.default.removeItem(at: file)
                }
            }
            // Imported metadata is a snapshot of the source identity, never the copy.
            // Recovery catalogs must use the cloned session/page identities too.
            let previousCatalog = try NativeArchive.fileURL(CatalogRecovery.previousPath, in: destination)
            if FileManager.default.fileExists(atPath: previousCatalog.path) {
                try encoder.encode(catalog).write(to: previousCatalog, options: .atomic)
            }
            let metadata = destination.appendingPathComponent("metadata.json")
            if FileManager.default.fileExists(atPath: metadata.path) { try FileManager.default.removeItem(at: metadata) }
        } catch {
            let original = error
            do {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            }
            catch { throw LibraryFailure.recoveryRequired(original.localizedDescription) }
            throw original
        }
    }
}
