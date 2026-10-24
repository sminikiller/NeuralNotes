import SwiftUI

@main
@MainActor
struct NeuralNotesApp: App {
    @State private var controller = AppController.shared

    var body: some Scene {
        WindowGroup(id: "library") {
            LibraryScene(controller: controller)
        }
    }
}

@MainActor
private struct LibraryScene: View {
    let controller: AppController
    @State private var session: LibraryViewModel?
    @State private var sceneError: String?
    var body: some View {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-photo-panel") {
                    PhotoCropUITestHost()
                } else {
                    libraryContent
                }
                #else
                libraryContent
                #endif
            }
            .tint(Brand.accent)
            .task {
                if controller.library == nil && controller.startupError == nil { controller.start() }
                if session == nil {
                    do { session = try controller.makeLibrarySession() }
                    catch { sceneError = error.localizedDescription }
                }
            }
    }
    @ViewBuilder private var libraryContent: some View {
                if let library = session {
                    LibraryView(model: library)
                } else if let error = sceneError ?? controller.startupError {
                    ContentUnavailableView {
                        Label("Libreria non disponibile", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("I dati esistenti sono stati conservati. \(error)")
                    } actions: {
                        Button("Riprova") {
                            controller.start()
                            do { session = try controller.makeLibrarySession(); sceneError = nil }
                            catch { sceneError = error.localizedDescription }
                        }
                    }
                } else {
                    ProgressView("Apertura libreria…")
                }
    }
}
