import Foundation
import Observation
import SwiftData
import NeuralNotesCore

@MainActor @Observable
final class AppController {
    static let shared = AppController()
    var library: LibraryViewModel?
    var startupError: String?
    private var repository: SwiftDataLibraryRepository?

    func makeLibrarySession() throws -> LibraryViewModel {
        guard let repository else { throw LibraryFailure.missingItem }
        let model = LibraryViewModel(repository: repository)
        try model.reload(); model.integrityIssues = try repository.integrityReport(); return model
    }

    func start() {
        guard repository == nil else { return }
        do {
            let manager = FileManager.default
            var support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true).appendingPathComponent("NeuralNotes")
            var documentRoot = try manager.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true).appendingPathComponent("Notebooks")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                support = support.deletingLastPathComponent().appendingPathComponent("NeuralNotes-UITests")
                documentRoot = support.appendingPathComponent("Notebooks")
                if ProcessInfo.processInfo.arguments.contains("--reset-ui-storage"),
                   manager.fileExists(atPath: support.path) {
                    try manager.removeItem(at: support)
                }
            }
            #endif
            try manager.createDirectory(at: support, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let configuration = ModelConfiguration("Library", schema: schema,
                url: support.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                               configurations: [configuration])
            let documents = try NativeDocumentStore(root: documentRoot)
            let repository = SwiftDataLibraryRepository(container: container, documents: documents)
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"), arguments.contains("--ui-audio-fixture"), try repository.notebooks().isEmpty {
                // UI-only metadata fixture in the isolated test container. No mic or ASR.
                let notebook = try repository.createNotebook(title: "Audio UI test", folderID: nil, cover: .lagoon)
                var session = AudioSession(title: "Trascrizione UI"); session.state = "finished"
                session.transcript = [TranscriptSegment(start: 0, duration: 2, text: "Testo da esportare")]
                var catalog = DocumentCatalog(); catalog.sessions = [session]
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let destination = documents.packageURL(for: notebook.documentID).appendingPathComponent("catalog.json")
                try encoder.encode(catalog).write(to: destination, options: .atomic)
            }
            #endif
            let model = LibraryViewModel(repository: repository)
            try model.reload()
            model.integrityIssues = try repository.integrityReport()
            self.repository = repository
            library = model
            startupError = nil
        } catch {
            // Never hide a storage failure by silently creating an empty/in-memory library.
            startupError = error.localizedDescription
        }
    }
}
