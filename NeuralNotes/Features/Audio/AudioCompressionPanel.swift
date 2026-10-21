import SwiftUI
import AVFoundation
import NeuralNotesCore

struct AudioCompressionEstimate: Sendable {
    var sessions: [UUID] = []
    var recoverableBytes: Int64 = 0
    static func measure(_ workspace: DocumentWorkspace) async throws -> Self {
        let sessions = try await workspace.catalog().sessions.filter { $0.state == "finished" && $0.trashedAt == nil }
        let pendingID = try await workspace.pendingAudioCompression()?.sessionID
        let package = workspace.package
        return await Task.detached(priority: .utility) {
            var result = Self(), seen = Set<String>()
            for session in sessions {
                var hasPCM = session.id == pendingID
                for segment in session.segments where seen.insert(segment.file).inserted {
                    let url = package.appendingPathComponent(segment.file)
                    guard AudioCompression.isPCM(url), let input = try? AVAudioFile(forReading: url),
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
                    let duration = Double(input.length) / input.processingFormat.sampleRate
                    guard duration.isFinite, duration > 0, duration <= 604800 else { continue }
                    hasPCM = true
                    result.recoverableBytes += max(0, Int64(size) - Int64(duration * 8000))
                }
                if hasPCM { result.sessions.append(session.id) }
            }
            return result
        }.value
    }
}

@MainActor
struct AudioCompressionPanel: View {
    let workspace: DocumentWorkspace
    var editor: EditorViewModel?
    @State private var estimate = AudioCompressionEstimate()
    @State private var controller: AudioController?
    @State private var busy = false
    @State private var error: String?
    @State private var hasPending = false
    @State private var job: Task<Void, Never>?
    private var available: Bool {
        if let editor {
            return editor.hasLease && editor.audio?.canTranscribe == true && editor.audio?.transcribingSessionID == nil && editor.audio?.playingSessionID == nil
        }
        return !EditorLeases.shared.isOpen(workspace.documentID)
    }
    var body: some View {
        List {
            Section("Registrazioni PCM") {
                LabeledContent("Lezioni comprimibili", value: "\(estimate.sessions.count)")
                LabeledContent("Spazio recuperabile stimato", value: ByteCountFormatter.string(fromByteCount: estimate.recoverableBytes, countStyle: .file))
                Text("AAC mono a 64 kbps occupa circa 29 MB/ora. Le copie di recupero possono trattenere gli originali; la stima non include tali copie.").font(.caption)
                Button("Comprimi registrazioni", systemImage: "arrow.down.right.and.arrow.up.left") { start() }
                    .disabled(busy || !available || estimate.sessions.isEmpty).accessibilityIdentifier("compressRecordings")
                if !available && !busy { Text("Termina o metti in pausa registrazione, trascrizione e ascolto. Se il quaderno è aperto altrove, chiudilo in quella finestra.").font(.caption) }
                if hasPending {
                    Button("Annulla conversione e conserva PCM", systemImage: "arrow.uturn.backward") { discard() }.disabled(busy || !available)
                    Text("Disponibile prima del cambio dei riferimenti. Dopo il cambio, riprendi la conversione per completare la pulizia.").font(.caption)
                }
            }
            if busy {
                Section {
                    ProgressView(controller?.compressionStatus ?? "Preparazione…")
                    Button("Metti in pausa") { job?.cancel(); controller?.compressionTask?.cancel() }
                }
            } else if let controller, !controller.compressionStatus.isEmpty { Text(controller.compressionStatus) }
            Text("L’originale viene rimosso solo dopo verifica di durata e tempi e salvataggio dei nuovi riferimenti. Un’interruzione lascia una conversione riprendibile.").font(.caption)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Comprimi registrazioni")
        .task { await refresh() }
        .onDisappear { job?.cancel(); controller?.compressionTask?.cancel() }
    }
    private func refresh() async {
        do { estimate = try await AudioCompressionEstimate.measure(workspace); hasPending = try await workspace.pendingAudioCompression() != nil }
        catch { self.error = error.localizedDescription }
    }
    private func discard() {
        guard available, !busy else { return }
        let owns = editor == nil
        if owns && !EditorLeases.shared.reserveCloud(workspace.documentID) { return }
        busy = true
        job = Task {
            defer { if owns { EditorLeases.shared.releaseCloud(workspace.documentID) }; busy = false; job = nil }
            do {
                if let plan = try await workspace.pendingAudioCompression() { try await workspace.discardAudioCompression(plan.id) }
                error = nil; controller?.compressionStatus = "Conversione annullata: originali PCM conservati."
            } catch { self.error = error.localizedDescription }
            await refresh()
        }
    }
    private func start() {
        guard available, !busy else { return }
        let ownsController = editor == nil
        if ownsController && !EditorLeases.shared.reserveCloud(workspace.documentID) { return }
        busy = true; error = nil
        let audio = editor?.audio ?? AudioController(workspace: workspace); controller = audio
        audio.error = nil
        job = Task {
            defer {
                if ownsController { EditorLeases.shared.releaseCloud(workspace.documentID) }
                busy = false; job = nil
            }
            await withTaskCancellationHandler {
                if ownsController { await audio.load() }
                await audio.compressionTask?.value
                do {
                    if let message = audio.error { throw CompressionPanelFailure(message: message) }
                    for id in estimate.sessions {
                        try Task.checkCancellation(); audio.error = nil
                        guard audio.canTranscribe, audio.transcribingSessionID == nil, audio.playingSessionID == nil else { throw CompressionPanelFailure(message: "Attendi la fine delle operazioni audio prima di comprimere.") }
                        audio.startCompression(id); await audio.compressionTask?.value
                        if let message = audio.error { throw CompressionPanelFailure(message: message) }
                    }
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
                if ownsController { await audio.close() }
            } onCancel: { Task { @MainActor in audio.compressionTask?.cancel() } }
            await refresh()
        }
    }
}

private struct CompressionPanelFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
