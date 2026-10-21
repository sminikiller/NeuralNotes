import AppIntents
import PencilKit
import NeuralNotesCore

struct QuickNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Crea una nota rapida"
    static var description = IntentDescription("Crea un quaderno nella Inbox di NeuralNotes, con un testo facoltativo.")
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Titolo", default: "Nota rapida") var noteTitle: String
    @Parameter(title: "Testo") var text: String?
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try LibraryName.validated(noteTitle)
        guard (text?.count ?? 0) <= 100_000 else { throw WorkspaceFailure.oversizedImport }
        let controller = AppController.shared; controller.start()
        guard let library = controller.library else { throw LibraryFailure.recoveryRequired(controller.startupError ?? "Libreria non disponibile") }
        guard await library.createQuickNote(title: name, initialText: text) != nil else { throw LibraryFailure.recoveryRequired(library.errorMessage ?? "Nota non creata") }
        return .result(dialog: "Nota creata nella Inbox di NeuralNotes.")
    }
}

struct NeuralNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuickNoteIntent(), phrases: ["Crea una nota in \(.applicationName)", "Nota rapida in \(.applicationName)"], shortTitle: "Nota rapida", systemImageName: "square.and.pencil")
    }
}
