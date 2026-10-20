import SwiftUI
import NeuralNotesCore

@MainActor
struct TranscriptReader: View {
    @Bindable var audio: AudioController
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    private var session: AudioSession? { audio.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let session {
                        if !session.hasCompletedTranscript { Text("Trascrizione parziale").foregroundStyle(.secondary) }
                        ForEach(TranscriptText.minutes(session.readableTranscript)) { minute in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { Task { await audio.play(session, at: minute.start) } } label: {
                                    Label(TranscriptText.clock(minute.start), systemImage: "play.circle")
                                }.disabled(audio.recording)
                                Text(minute.text).frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                        if !session.hasTranscriptText { Text("Nessun testo riconosciuto.") }
                    }
                }.padding()
            }.accessibilityIdentifier("transcriptReader")
                .navigationTitle(session?.title ?? "Trascrizione")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
