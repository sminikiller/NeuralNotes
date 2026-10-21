import Foundation

extension DocumentWorkspace {
    /// Import as new pages. The manifest is the final commit: existing pages and
    /// media are never replaced, including when the imported file is our own backup.
    public func appendNative(from source: URL) throws -> [PageSnapshot] {
        guard try catalog().sessions.allSatisfy({ $0.state != "recording" }) else {
            throw LibraryFailure.recoveryRequired("Metti in pausa la registrazione prima di importare le pagine.")
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("NN-merge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try NativeDocumentStore(root: scratch)
        let importedID = UUID(), importedBook = UUID()
        _ = try NativeImport.copy(from: source, into: store, documentID: importedID, notebookID: importedBook)
        let incoming = store.packageURL(for: importedID)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func read<T: Decodable>(_ path: String) throws -> T {
            try decoder.decode(T.self, from: Data(contentsOf: NativeArchive.fileURL(path, in: incoming)))
        }
        let imported: DocumentManifest = try read("manifest.json")
        var index = try manifest(), combined = try catalog()
        guard Set(index.pageIDs).isDisjoint(with: imported.pageIDs) else { throw LibraryFailure.corruptDocument }
        let namespace = "import-\(UUID())"
        var files: [String: String] = [:]
        for folder in ["drawings", "images", "audio", "attachments"] {
            let directory = incoming.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            for file in try PackageFiles.list(in: directory) {
                try Task.checkCancellation()
                let relative = file.path
                let path = "\(folder)/\(namespace)/\(relative)"
                let destination = try url(path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file.url, to: destination)
                files["\(folder)/\(relative)"] = path
            }
        }
        func mapped(_ file: String) throws -> String {
            guard let value = files[file] else { throw LibraryFailure.corruptDocument }; return value
        }
        func reference(_ original: SourceReference) -> SourceReference {
            guard original.documentID == importedID else { return original }
            return SourceReference(documentID: index.documentID, pageID: original.pageID,
                audioSessionID: original.audioSessionID, seconds: original.seconds, pageRevision: original.pageRevision)
        }
        var pages: [PageSnapshot] = []
        for id in imported.pageIDs {
            var page: PageSnapshot = try read("pages/\(id).json")
            page.drawingFile = try page.drawingFile.map(mapped)
            page.previousDrawingFile = try page.previousDrawingFile.map(mapped)
            page.pdfFile = try page.pdfFile.map(mapped)
            for position in page.images.indices { page.images[position].file = try mapped(page.images[position].file) }
            for position in page.texts.indices {
                if var link = page.texts[position].pageLink, link.documentID == importedID {
                    link.documentID = index.documentID; page.texts[position].pageLink = link
                }
            }
            try write(page, "pages/\(page.id).json")
            pages.append(page)
        }
        let catalogFile = incoming.appendingPathComponent("catalog.json")
        if FileManager.default.fileExists(atPath: catalogFile.path) {
            var catalog: DocumentCatalog = try read("catalog.json")
            for i in catalog.attachments.indices { catalog.attachments[i].file = try mapped(catalog.attachments[i].file) }
            for i in catalog.sessions.indices {
                for j in catalog.sessions[i].segments.indices { catalog.sessions[i].segments[j].file = try mapped(catalog.sessions[i].segments[j].file) }
                if var chunks = catalog.sessions[i].transcriptionChunks {
                    for j in chunks.indices { chunks[j].file = try mapped(chunks[j].file) }
                    catalog.sessions[i].transcriptionChunks = chunks
                }
            }
            combined.attachments += catalog.attachments; combined.sessions += catalog.sessions
            if let sections = catalog.sections {
                let merged = (combined.sections ?? []) + sections
                try NotebookSections.validate(merged); combined.sections = merged
            }
            if let reviews = catalog.reviewLog {
                combined.reviewLog = Array(((combined.reviewLog ?? []) + reviews).sorted { $0.date < $1.date }.suffix(10_000))
            }
            var quizzes = (catalog.quizHistory ?? []).map { $0.copied(remapping: reference) }
            if let active = catalog.activeQuiz?.copied(remapping: reference) {
                if combined.activeQuiz == nil { combined.activeQuiz = active } else { quizzes.append(active) }
            }
            combined.quizHistory = Array(((combined.quizHistory ?? []) + quizzes).suffix(10))
            if let conversation = catalog.conversation {
                let importedTurns = conversation.map { turn in
                    AIConversationTurn(question: turn.question, answer: AIArtifact(text: turn.answer.text,
                        references: turn.answer.references.map(reference), provider: turn.answer.provider,
                        createdAt: turn.answer.createdAt, task: turn.answer.task))
                }
                combined.conversation = Array(((combined.conversation ?? []) + importedTurns).suffix(20))
            }
            if let glossary = catalog.glossary {
                combined.glossary = Array(((combined.glossary ?? []) + glossary.map { entry in
                    var copy = entry; copy.id = UUID(); copy.references = entry.references.map(reference); return copy
                }).suffix(1000))
            }
            if let cards = catalog.studyCards {
                combined.studyCards = (combined.studyCards ?? []) + cards.map { card in
                    var result = card; result.source = reference(card.source); return result
                }
            }
        }
        let artifacts = incoming.appendingPathComponent("artifacts")
        if FileManager.default.fileExists(atPath: artifacts.path) {
            for file in try FileManager.default.contentsOfDirectory(at: artifacts, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                let artifact = try decoder.decode(AIArtifact.self, from: Data(contentsOf: file))
                try saveArtifact(AIArtifact(text: artifact.text, references: artifact.references.map(reference),
                    provider: artifact.provider, createdAt: artifact.createdAt, task: artifact.task))
            }
        }
        try write(combined, "catalog.json")
        index.pageIDs += imported.pageIDs
        try write(index, "manifest.json")
        return pages
    }
}
