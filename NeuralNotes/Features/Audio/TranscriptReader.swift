import SwiftUI
import NeuralNotesCore

@MainActor
struct TranscriptReader: View {
    @Bindable var audio: AudioController
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var chapters = false
    private var session: AudioSession? { audio.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let session {
                        Picker("Visualizzazione", selection: $chapters) { Text("Per minuto").tag(false); Text("Per capitoli").tag(true) }.pickerStyle(.segmented)
                        if !session.hasCompletedTranscript { Text("Trascrizione parziale").foregroundStyle(.secondary) }
                        if chapters {
                            Text("Capitoli ogni 5 minuti e nei punti segnati da te. Nessuna frase viene riassunta o eliminata.").font(.caption).foregroundStyle(.secondary)
                            ForEach(TranscriptChapters.make(session: session)) { chapter in
                                VStack(alignment: .leading, spacing: 12) {
                                    Button { Task { await audio.play(session, at: chapter.start) } } label: { Label(chapter.title, systemImage: "play.circle").font(.headline) }.disabled(audio.recording)
                                    ForEach(chapter.minutes) { minute in Text("[\(TranscriptText.clock(minute.start))] \(minute.text)").textSelection(.enabled) }
                                    if chapter.minutes.isEmpty { Text("Nessun testo riconosciuto in questo intervallo.").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        } else {
                        ForEach(TranscriptText.minutes(session.readableTranscript)) { minute in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { Task { await audio.play(session, at: minute.start) } } label: {
                                    Label(TranscriptText.clock(minute.start), systemImage: "play.circle")
                                }.disabled(audio.recording)
                                Text(minute.text).frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                        }
                        if !session.hasTranscriptText { Text("Nessun testo riconosciuto.") }
                    }
                }.padding()
            }.accessibilityIdentifier("transcriptReader")
                .navigationTitle(session?.title ?? "Trascrizione")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
                .toolbar { ToolbarItem(placement: .primaryAction) {
                    if let session { ShareLink(item: TranscriptMarkdownFile(session: session), preview: SharePreview(session.title)) { Label("Esporta capitoli", systemImage: "square.and.arrow.up") }.disabled(!session.hasTranscriptText) }
                } }
        }
    }
}
