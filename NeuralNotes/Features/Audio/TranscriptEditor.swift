import SwiftUI
import NeuralNotesCore

@MainActor
struct TranscriptEditor: View {
    let audio: AudioController
    let session: AudioSession
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var blocks: [TranscriptMinute]
    @State private var error: String?
    @State private var saving = false
    init(audio: AudioController, session: AudioSession) {
        self.audio = audio; self.session = session
        _title = State(initialValue: session.title)
        _blocks = State(initialValue: TranscriptText.minutes(session.readableTranscript))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Nome della registrazione e trascrizione") { TextField("Nome", text: $title).accessibilityIdentifier("transcriptTitle") }
                ForEach($blocks) { $block in
                    Section(TranscriptText.clock(block.start)) {
                        TextEditor(text: $block.text).frame(minHeight: 110)
                    }
                }
                Section { Text("Le correzioni restano associate al minuto originale e non modificano l’audio.").font(.caption) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving)
            .navigationTitle("Rinomina e correggi")
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") {
                    Task {
                        saving = true; defer { saving = false }
                        do { try await audio.saveTranscript(session.id, title: title, blocks: blocks); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving || (try? LibraryName.validated(title)) == nil) }
            }
        }
    }
}
