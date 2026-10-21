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
    @State private var renamingBookmark: AudioBookmark?
    @State private var bookmarkSessionID: UUID?
    @State private var bookmarkName = ""
    @State private var importingAudio = false

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
                        if session.hasTranscriptText {
                            Button("Visualizza trascrizione", systemImage: "doc.text.magnifyingglass") {
                                guard presentation == nil else { return }; presentation = .read(session.id)
                            }.buttonStyle(.borderless).accessibilityIdentifier("transcriptRead-\(session.id)")
                            Text(TranscriptText.firstMinuteText(session.readableTranscript))
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
                        ShareLink(item: TranscriptFile(session: session), preview: SharePreview(session.title)) {
                            Label("Esporta testo", systemImage: "square.and.arrow.up")
                        }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("transcriptExport-\(session.id)")
                            .disabled(!session.hasTranscriptText)
                        Button("Segnalibro qui", systemImage: "bookmark.badge.plus") { Task { await audio.addBookmark(sessionID: session.id) } }.buttonStyle(.borderless)
                            .disabled(audio.transcribingSessionID != nil)
                        ForEach(session.bookmarks ?? []) { bookmark in
                            HStack {
                                Button("\(clock(bookmark.seconds)) · \(bookmark.title)", systemImage: "bookmark.fill") { Task { await audio.play(session, at: bookmark.seconds) } }.buttonStyle(.borderless)
                                Spacer()
                                Button("Elimina segnalibro", systemImage: "xmark", role: .destructive) { Task { await audio.removeBookmark(bookmark, sessionID: session.id) } }.labelStyle(.iconOnly).buttonStyle(.borderless).disabled(audio.transcribingSessionID != nil)
                            }
                            .contextMenu {
                                Button("Rinomina segnalibro", systemImage: "pencil") { bookmarkName = bookmark.title; bookmarkSessionID = session.id; renamingBookmark = bookmark }
                                    .disabled(audio.transcribingSessionID != nil)
                            }
                        }
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
                            if audio.transcriptionTask != nil {
                                Button("Pausa trascrizione", systemImage: "pause.circle") { audio.transcriptionTask?.cancel() }
                            }
                        } else if audio.transcriptionStatusSessionID == session.id, !audio.transcriptionStatus.isEmpty {
                            Text(audio.transcriptionStatus).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("transcriptionStatus")
                        }
                        DisclosureGroup("Diagnosi trascrizione") {
                            Button("Prova il primo blocco", systemImage: "stethoscope") { Task { await audio.probeFirstWindow(session) } }
                                .buttonStyle(.borderless)
                                .disabled(audio.transcribingSessionID != nil || audio.recording || session.segments.isEmpty)
                                .accessibilityIdentifier("transcriptProbe-\(session.id)")
                            Text("Riconosce solo i primi secondi e mostra metodo, tempo e testo. Utile se la trascrizione si ferma.")
                                .font(.caption).foregroundStyle(.secondary)
                            TranscriptionLogView()
                        }
                    }
                }
                Section("Ascolto") {
                    Picker("Velocità", selection: Binding(get: { audio.playbackRate }, set: { audio.setPlaybackRate($0) })) {
                        ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Text("\(rate, specifier: "%.2g")×").tag(rate) }
                    }
                    Toggle("Rivela gli appunti al momento dell’audio", isOn: $audio.replayInk)
                    Text("Il replay mostra i tratti collegati fino al momento ascoltato. Il disegno originale è conservato.").font(.caption)
                    Button("Importa audio da File", systemImage: "waveform.badge.plus") { importingAudio = true }
                        .disabled(audio.recording || audio.transitioning || audio.transcribingSessionID != nil)
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
            .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let url): Task { await audio.importAudio(url) }
                case .failure(let error): audio.error = error.localizedDescription
                }
            }
            .onChange(of: audio.playback) { _, value in if !seeking { seekSeconds = value } }
            .alert("Nome del segnalibro", isPresented: Binding(get: { renamingBookmark != nil }, set: { if !$0 { renamingBookmark = nil } })) {
                TextField("Nome", text: $bookmarkName)
                Button("Salva") { if let bookmark = renamingBookmark, let id = bookmarkSessionID { let name = bookmarkName; Task { await audio.renameBookmark(bookmark.id, sessionID: id, title: name) } }; renamingBookmark = nil }
                Button("Annulla", role: .cancel) { renamingBookmark = nil }
            }
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
