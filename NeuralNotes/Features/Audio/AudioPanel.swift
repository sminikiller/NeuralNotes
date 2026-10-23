import SwiftUI
import UniformTypeIdentifiers
import NeuralNotesCore

private enum AudioPresentation: Identifiable {
    case read(UUID), edit(AudioSession), export(AudioExportBundle), textExport(URL)
    var id: String {
        switch self { case .read(let id): return "read-\(id)"
        case .edit(let session): return "edit-\(session.id)"
        case .export(let bundle): return bundle.directory.lastPathComponent
        case .textExport(let url): return url.lastPathComponent }
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
    @State private var scope = AudioLibraryScope.recent
    @State private var query = ""
    @State private var exporting = false
    @State private var exportJob: Task<Void, Never>?
    @State private var exported: AudioExportBundle?
    @State private var exportedText: URL?
    @State private var pendingMutation: PendingAudioMutation?

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
                .disabled(audio.transitioning || audio.transcribingSessionID != nil || audio.compressionTask != nil || exporting)
                if !audio.compressionStatus.isEmpty {
                    Section("Compressione audio") {
                        Text(audio.compressionStatus).font(.caption)
                        if audio.compressionTask != nil {
                            ProgressView()
                            Button("Metti in pausa la compressione") { audio.compressionTask?.cancel() }
                        }
                    }
                }
                Section("Lezioni salvate") {
                    Picker("Raccolta", selection: $scope) {
                        Text("Recenti").tag(AudioLibraryScope.recent)
                        Text("Archivio").tag(AudioLibraryScope.archived)
                        Text("Cestino").tag(AudioLibraryScope.trash)
                    }.pickerStyle(.segmented).accessibilityIdentifier("audioLibraryScope")
                    if exporting { ProgressView("Preparazione dell’esportazione…"); Button("Annulla esportazione") { exportJob?.cancel() } }
                    if scope == .trash { Text("Il cestino conserva audio, testo e collegamenti e occupa ancora spazio. Puoi ripristinare le lezioni.").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(AudioLibraryQuery.sessions(audio.sessions, scope: scope, query: query)) { session in sessionSection(session) }
                Section("Ascolto") {
                    Picker("Velocità", selection: Binding(get: { audio.playbackRate }, set: { audio.setPlaybackRate($0) })) {
                        ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Text("\(rate, specifier: "%.2g")×").tag(rate) }
                    }
                    Toggle("Rivela gli appunti al momento dell’audio", isOn: $audio.replayInk)
                    Text("Il replay mostra i tratti collegati fino al momento ascoltato. Il disegno originale è conservato.").font(.caption)
                    Button("Importa audio da File", systemImage: "waveform.badge.plus") { importingAudio = true }
                        .disabled(!audio.canTranscribe || audio.transcribingSessionID != nil)
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
            .accessibilityIdentifier("audioLibraryList")
            .navigationTitle("Audio e trascrizioni")
            .searchable(text: $query, prompt: "Nome della registrazione")
            .interactiveDismissDisabled(exporting)
            .onDisappear { exportJob?.cancel() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(item: $presentation, onDismiss: finishPresentation) { item in
                switch item {
                case .read(let id): TranscriptReader(audio: audio, sessionID: id)
                case .edit(let session): TranscriptEditor(audio: audio, session: session)
                case .export(let bundle): AudioFileShare(files: bundle.files)
                case .textExport(let url): AudioFileShare(files: [url])
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

    @ViewBuilder
    private func sessionSection(_ session: AudioSession) -> some View {
        if session.trashedAt != nil {
            Section(session.title) {
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Button("Ripristina registrazione", systemImage: "arrow.uturn.backward") { Task { await audio.organize(session.id, action: .restore) } }
                    .disabled(!canOrganize(session)).accessibilityIdentifier("audioRestore-\(session.id)")
            }
        } else {
            Section(session.title) {
                Text("\(clock(session.duration)) · \(session.state == "finished" ? "Conclusa" : "In corso / recuperata")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                transcriptControls(session)
                organizationControls(session)
                bookmarkControls(session)
                playbackControls(session)
                recognitionControls(session)
            }
        }
    }
    @ViewBuilder private func transcriptControls(_ session: AudioSession) -> some View {
                if session.hasTranscriptText {
                    Button("Visualizza trascrizione", systemImage: "doc.text.magnifyingglass") {
                        guard presentation == nil, !exporting else { return }; presentation = .read(session.id)
                    }.buttonStyle(.borderless).accessibilityIdentifier("transcriptRead-\(session.id)")
                    Text(TranscriptText.firstMinuteText(session.readableTranscript))
                        .lineLimit(3).foregroundStyle(.secondary)
                } else if session.transcriptionComplete == true {
                    Text("Analisi completata senza testo riconosciuto. Ascolta l’audio e premi Riprova trascrizione.")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("transcriptEmpty")
                }
                Button("Rinomina / correggi", systemImage: "pencil") {
                    guard presentation == nil, !exporting else { return }; presentation = .edit(session)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("transcriptEdit-\(session.id)")
                .disabled(!audio.canTranscribe || audio.transcribingSessionID != nil || session.state != "finished")
                Button("Esporta testo", systemImage: "square.and.arrow.up") { exportTranscript(session) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("transcriptExport-\(session.id)")
                    .disabled(!session.hasTranscriptText || exporting)
    }
    @ViewBuilder private func bookmarkControls(_ session: AudioSession) -> some View {
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
    }
    @ViewBuilder private func playbackControls(_ session: AudioSession) -> some View {
                Button("Riproduci", systemImage: "play.circle") { Task { await audio.play(session) } }
                    .disabled(audio.recording || audio.compressionTask != nil)
                if audio.playingSessionID == session.id {
                    Slider(value: $seekSeconds, in: 0...max(session.duration, 0.1), onEditingChanged: { editing in
                        seeking = editing
                        if !editing { Task { await audio.play(session, at: seekSeconds) } }
                    })
                    Text(clock(audio.playback)).monospacedDigit()
                    HStack {
                        Button("−15 s", systemImage: "gobackward.15") { Task { await audio.skipPlayback(by: -15) } }
                        Spacer()
                        Button("+15 s", systemImage: "goforward.15") { Task { await audio.skipPlayback(by: 15) } }
                    }.buttonStyle(.borderless)
                    Button("Ferma riproduzione") { audio.stopPlayback() }
                }
    }
    @ViewBuilder private func recognitionControls(_ session: AudioSession) -> some View {
                Button(transcriptionLabel(session), systemImage: "text.bubble") { audio.startTranscription(session) }
                    .disabled(!audio.canTranscribe || audio.transcribingSessionID != nil || session.state != "finished" || isComplete(session))
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
                LectureNotesSection(audio: audio, model: model, session: session)
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
    private func canOrganize(_ session: AudioSession) -> Bool {
        audio.canTranscribe && !exporting && audio.transcribingSessionID == nil && audio.active?.id != session.id && session.state == "finished"
    }
    private func organizationControls(_ session: AudioSession) -> some View {
        HStack {
            Button("Esporta audio e trascrizione", systemImage: "square.and.arrow.up") { prepareExport(session) }
                .disabled(!canOrganize(session)).accessibilityIdentifier("audioFilesExport-\(session.id)")
            Spacer()
            Menu {
                Button(session.isArchived == true ? "Sposta nei recenti" : "Archivia", systemImage: "archivebox") {
                    Task { await audio.organize(session.id, action: .archive(session.isArchived != true)) }
                }
                Button("Cancella solo la trascrizione", systemImage: "text.badge.minus", role: .destructive) {
                    pendingMutation = PendingAudioMutation(sessionID: session.id, action: .clearTranscript, title: "Cancella trascrizione", detail: "Il testo e le correzioni saranno rimossi. L’audio originale resta salvato e potrà essere trascritto di nuovo.")
                }.disabled(!session.hasTranscriptText)
                Button("Sposta nel cestino", systemImage: "trash", role: .destructive) {
                    pendingMutation = PendingAudioMutation(sessionID: session.id, action: .trash, title: "Sposta nel cestino", detail: "La lezione verrà nascosta dai recenti e dalla ricerca. I file e i collegamenti restano conservati e ripristinabili.")
                }
            } label: { Label("Organizza registrazione", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .disabled(!canOrganize(session)).accessibilityIdentifier("audioOrganize-\(session.id)")
        }.buttonStyle(.borderless)
        .confirmationDialog(pendingMutation?.title ?? "Organizza registrazione", isPresented: Binding(get: { pendingMutation?.sessionID == session.id }, set: { if !$0 { pendingMutation = nil } }), titleVisibility: .visible) {
            if let pendingMutation {
                Button(pendingMutation.title, role: .destructive) { let action = pendingMutation; self.pendingMutation = nil; Task { await audio.organize(action.sessionID, action: action.action) } }
            }
            Button("Annulla", role: .cancel) { pendingMutation = nil }
        } message: { Text(pendingMutation?.detail ?? "") }
    }
    private func prepareExport(_ session: AudioSession) {
        guard canOrganize(session), presentation == nil else { return }; exporting = true
        exportJob = Task {
            defer { exporting = false }
            do {
                let bundle = try await audio.workspace.exportAudioSession(session.id)
                if Task.isCancelled { try? bundle.removeTemporaryFiles(); return }
                exported = bundle; presentation = .export(bundle)
            } catch is CancellationError { }
            catch { audio.error = "Esportazione interrotta: \(error.localizedDescription). Gli originali sono conservati." }
        }
    }
    private func exportTranscript(_ session: AudioSession) {
        guard session.hasTranscriptText, presentation == nil, !exporting else { return }; exporting = true
        exportJob = Task {
            defer { exporting = false }
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    let text = TranscriptText.export(title: session.title, segments: session.readableTranscript,
                        complete: session.hasCompletedTranscript)
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Trascrizione-\(UUID()).txt")
                    try text.write(to: file, atomically: true, encoding: .utf8); return file
                }.value
                guard !Task.isCancelled, presentation == nil else { try? FileManager.default.removeItem(at: file); return }
                exportedText = file; presentation = .textExport(file)
            } catch is CancellationError { }
            catch { audio.error = "Esportazione interrotta: \(error.localizedDescription). Il testo originale è conservato." }
        }
    }
    private func finishPresentation() {
        if let exported { try? exported.removeTemporaryFiles() }; exported = nil
        if let exportedText { try? FileManager.default.removeItem(at: exportedText) }; exportedText = nil
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
        TranscriptText.clock(seconds)
    }
}

private struct PendingAudioMutation {
    let sessionID: UUID
    let action: AudioLibraryAction
    let title: String
    let detail: String
}

@MainActor
private struct AudioFileShare: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
