import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import NeuralNotesCore

struct LectureNotesFile: Transferable {
    let title: String
    let notes: LectureNotes
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { value in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sbobina-\(UUID()).md")
            try LectureNotesPlanner.markdown(title: value.title, notes: value.notes).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// "Sbobina con l’AI" inside each recording of the Audio panel.
@MainActor
struct LectureNotesSection: View {
    @Bindable var audio: AudioController
    let model: EditorViewModel
    let session: AudioSession
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var reading = false
    var body: some View {
        DisclosureGroup("Sbobina con l’AI") {
            if let notes = session.lectureNotes {
                Text(summary(notes)).font(.caption).foregroundStyle(stale ? Color.orange : Color.secondary)
                Button("Leggi la sbobina", systemImage: "doc.richtext") { reading = true }.buttonStyle(.borderless)
            }
            if audio.notesSessionID == session.id {
                ProgressView(value: audio.notesProgress)
                Text(audio.notesStatus).font(.caption)
                Button("Pausa sbobina", systemImage: "pause.circle") { audio.notesTask?.cancel() }.buttonStyle(.borderless)
            } else {
                if audio.notesStatusSessionID == session.id, !audio.notesStatus.isEmpty {
                    Text(audio.notesStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let title = startTitle {
                    Button(title, systemImage: "sparkles") { audio.startLectureNotes(session, configuration: configuration, consentKey: consentKey) }
                        .buttonStyle(.borderless).disabled(!canStart)
                }
                Button("Connessione AI", systemImage: "slider.horizontal.3") { configuring = true }.buttonStyle(.borderless)
            }
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .task { if consentKey == nil { consentKey = await AIEngineRouter.restoredConsent(configuration) } }
        .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
        .sheet(isPresented: $reading) { LectureNotesReader(audio: audio, model: model, sessionID: session.id) }
    }
    private var stale: Bool { session.lectureNotes.map { $0.fingerprint != LectureNotesPlanner.fingerprint(session) } ?? false }
    private var canStart: Bool {
        configuration.engine != .offline && consentKey == configuration.consentKey && audio.canTranscribe && audio.notesTask == nil
            && audio.transcribingSessionID == nil && session.hasTranscriptText && session.state == "finished" && session.trashedAt == nil
    }
    private var startTitle: String? {
        guard let notes = session.lectureNotes else { return "Crea sbobina con l’AI" }
        if stale { return "Aggiorna la sbobina" }
        return notes.isComplete ? nil : "Riprendi sbobina"
    }
    private var hint: String {
        if !session.hasTranscriptText { return "Trascrivi prima la registrazione: la sbobina riscrive il testo riconosciuto." }
        if configuration.engine == .offline { return "Scegli un motore AI nella Connessione AI: la modalità offline non riscrive il testo." }
        if consentKey != configuration.consentKey { return "Attiva il consenso nella Connessione AI per inviare la trascrizione a \(configuration.engine.title)." }
        return "Riscrive la trascrizione in appunti puliti, un capitolo alla volta (cinque minuti o un tuo segnalibro), con i tempi dell’audio. Ogni capitolo viene salvato appena pronto."
    }
    private func summary(_ notes: LectureNotes) -> String {
        if stale { return "La trascrizione è cambiata dopo la sbobina: aggiornala per allinearla." }
        return notes.isComplete ? "Sbobina completa · \(notes.blocks.count) capitoli" : "Sbobina parziale · \(notes.completedCount) di \(notes.blocks.count) capitoli"
    }
}

@MainActor
struct LectureNotesReader: View {
    @Bindable var audio: AudioController
    let model: EditorViewModel
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var inserting = false
    private var session: AudioSession? { audio.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            List {
                if let session, let notes = session.lectureNotes {
                    Section {
                        Text(notes.isComplete ? "Rielaborazione AI completa della trascrizione." : "Rielaborazione parziale: \(notes.completedCount) di \(notes.blocks.count) capitoli.")
                        Text("Controlla sull’audio i passaggi importanti: la trascrizione automatica può contenere errori.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(notes.blocks) { block in
                        Section {
                            Button("Ascolta da \(TranscriptText.clock(block.start))", systemImage: "play.circle") { Task { await audio.play(session, at: block.start) } }
                                .buttonStyle(.borderless)
                            Text(block.text.map { $0.isEmpty ? "Nessun testo riconosciuto in questo capitolo." : $0 } ?? "Capitolo non ancora elaborato.")
                                .textSelection(.enabled)
                        } header: { Text(block.title) }
                    }
                } else { Text("Nessuna sbobina salvata per questa registrazione.") }
            }
            .navigationTitle("Sbobina")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                if let session, let notes = session.lectureNotes {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ShareLink(item: LectureNotesFile(title: session.title, notes: notes), preview: SharePreview("Sbobina · \(session.title)")) {
                                Label("Esporta Markdown", systemImage: "square.and.arrow.up")
                            }
                            Button("Inserisci come pagine del quaderno", systemImage: "doc.badge.plus") { insert(session, notes) }.disabled(inserting)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Azioni sbobina")
                    }
                }
            }
        }
    }
    private func insert(_ session: AudioSession, _ notes: LectureNotes) {
        guard !inserting else { return }; inserting = true
        Task {
            defer { inserting = false }
            let pages = LectureNotesPlanner.pages(LectureNotesPlanner.markdown(title: session.title, notes: notes))
            if await model.appendTextPages(pages, label: "Inserisci sbobina") { model.status = "Sbobina inserita in \(pages.count) pagine"; dismiss() }
        }
    }
}
