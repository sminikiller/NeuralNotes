import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import NeuralNotesCore

private enum AudioPresentation: Identifiable {
    case read(UUID), edit(AudioSession)
    var id: String {
        switch self { case .read(let id): return "read-\(id)"
        case .edit(let session): return "edit-\(session.id)" }
    }
}

private struct TranscriptFile: Transferable {
    let session: AudioSession
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            let text = TranscriptText.export(title: item.session.title, segments: item.session.readableTranscript,
                complete: item.session.hasCompletedTranscript)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trascrizione-\(UUID()).txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

@MainActor
struct AudioPanel: View {
    @Bindable var audio: AudioController
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var presentation: AudioPresentation?
    @State private var seekSeconds: Double = 0
    @State private var seeking = false

    var body: some View {
        NavigationStack {
            List {
                Section("Registrazione") {
                    Text(clock(audio.elapsed)).font(.largeTitle.monospacedDigit())
                    if audio.recording {
                        Button("Pausa", systemImage: "pause.circle") { Task { await audio.pause() } }
                    } else {
                        Button(audio.paused ? "Riprendi registrazione" : "Nuova registrazione", systemImage: "mic.circle") {
                            Task { await audio.start() }
                        }
                    }
                    if audio.active != nil {
                        Button("Termina e salva", systemImage: "stop.circle") { Task { await audio.finish() } }
                    }
                    Text("Puoi chiudere questo pannello e scrivere mentre registri. I tratti nuovi vengono associati al momento dell’audio.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(audio.backgroundAudioConfigured ? "La registrazione può continuare anche in standby e passando a un’altra app. Pausa e Termina restano manuali." : "Questa esecuzione non espone l’audio in background: verifica il supporto del progetto o del runner Swift Playground.")
                        .font(.caption).foregroundStyle(audio.backgroundAudioConfigured ? Color.secondary : Color.orange)
                }
                .disabled(audio.transitioning || audio.transcribingSessionID != nil)
                ForEach(audio.sessions) { session in
                    Section(session.title) {
                        Text("\(clock(session.duration)) · \(session.state == "finished" ? "Conclusa" : "In corso / recuperata")")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Riproduci", systemImage: "play.circle") { Task { await audio.play(session) } }
                        if audio.playingSessionID == session.id {
                            Slider(value: $seekSeconds, in: 0...max(session.duration, 0.1), onEditingChanged: { editing in
                                seeking = editing
                                if !editing { Task { await audio.play(session, at: seekSeconds) } }
                            })
                            Text(clock(audio.playback)).monospacedDigit()
                            Button("Ferma riproduzione") { audio.stopPlayback() }
                        }
                        Button(transcriptionLabel(session), systemImage: "text.bubble") { audio.startTranscription(session) }
                            .disabled(audio.transcribingSessionID != nil || audio.recording || session.state != "finished" || isComplete(session))
                        if audio.transcribingSessionID == session.id {
                            ProgressView(value: audio.transcriptionProgress)
                            Text(audio.transcriptionStatus).font(.caption)
                            Button("Pausa trascrizione", systemImage: "pause.circle") { audio.transcriptionTask?.cancel() }
                        }
                        if session.hasTranscriptText {
                            Button("Visualizza trascrizione", systemImage: "doc.text.magnifyingglass") {
                                guard presentation == nil else { return }; presentation = .read(session.id)
                            }.buttonStyle(.borderless).accessibilityIdentifier("transcriptRead-\(session.id)")
                            Text(TranscriptText.minutes(session.readableTranscript).first?.text ?? "")
                                .lineLimit(3).foregroundStyle(.secondary)
                        } else if session.transcriptionComplete == true {
                            Text("Analisi completata senza testo riconosciuto. Ascolta l’audio e premi Riprova trascrizione.")
                                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("transcriptEmpty")
                        }
                        Button("Rinomina / correggi", systemImage: "pencil") {
                            guard presentation == nil else { return }; presentation = .edit(session)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("transcriptEdit-\(session.id)")
                        .disabled(audio.transcribingSessionID != nil)
                        ShareLink(item: TranscriptFile(session: session)) { Label("Esporta testo", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("transcriptExport-\(session.id)")
                            .disabled(!session.hasTranscriptText)
                    }
                }
                if let page = model.page, !page.anchors.isEmpty {
                    Section("Momenti collegati a questa pagina") {
                        ForEach(page.anchors) { anchor in
                            Button("Appunto a \(clock(anchor.seconds))", systemImage: "waveform") {
                                if let session = audio.sessions.first(where: { $0.id == anchor.audioSessionID }) {
                                    Task { await audio.play(session, at: anchor.seconds) }
                                }
                            }
                        }
                    }
                }
                if let error = audio.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Audio e trascrizioni")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(item: $presentation) { item in
                switch item {
                case .read(let id): TranscriptReader(audio: audio, sessionID: id)
                case .edit(let session): TranscriptEditor(audio: audio, session: session)
                }
            }
            .onChange(of: audio.playback) { _, value in if !seeking { seekSeconds = value } }
        }
    }

    private func isComplete(_ session: AudioSession) -> Bool {
        session.hasCompletedTranscript
    }
    private func transcriptionLabel(_ session: AudioSession) -> String {
        if audio.transcribingSessionID == session.id { return "Trascrizione in corso…" }
        if isComplete(session) { return "Trascrizione salvata" }
        if session.transcriptionComplete == true && !session.hasTranscriptText { return "Riprova trascrizione" }
        return session.transcriptionChunks?.isEmpty == false ? "Riprendi trascrizione" : "Trascrivi in italiano sul dispositivo"
    }
    private func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
