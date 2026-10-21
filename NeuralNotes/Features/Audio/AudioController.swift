import AVFoundation
import Observation
import NeuralNotesCore

@MainActor @Observable
final class AudioController: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    let workspace: DocumentWorkspace
    var sessions: [AudioSession] = []
    var active: AudioSession?
    var recording = false
    var paused = false
    var elapsed: Double = 0
    var replayInk = false
    private(set) var playbackRate: Double = 1
    var playback: Double = 0
    var playingSessionID: UUID?
    var error: String?
    var transcribingSessionID: UUID?
    var transcriptionProgress = 0.0
    var transcriptionStatus = ""
    /// Session whose last transcription message stays visible after the job ends.
    var transcriptionStatusSessionID: UUID?
    @ObservationIgnored var transcriptionTask: Task<Void, Never>?
    var compressingSessionID: UUID?
    var compressionStatus = ""
    @ObservationIgnored var compressionTask: Task<Void, Never>?
    @ObservationIgnored var windowRecognition: (@MainActor (URL, SpeechWindow, String) async throws -> [TranscriptSegment])?
    /// Seconds per recognition block; tests use short blocks to simulate long recordings.
    @ObservationIgnored var transcriptionWindowLength: Double = 45
    var canTranscribe: Bool { !closed && !recording && !transitioning && compressionTask == nil && compressingSessionID == nil }
    var backgroundAudioConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true
    }
    private(set) var transitioning = false
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var interruption: NSObjectProtocol?
    @ObservationIgnored private var routeChange: NSObjectProtocol?
    @ObservationIgnored private var playingIndex = 0
    @ObservationIgnored private var playbackGeneration = UUID()
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var suspended = false

    var recordingAnchor: (UUID, Double)? {
        guard recording, let active, let segment = active.segments.last else { return nil }
        return (active.id, segment.start + (recorder?.currentTime ?? 0))
    }

    init(workspace: DocumentWorkspace) {
        self.workspace = workspace
        super.init()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let kind = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      kind == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in
                    guard let self, self.recording else { return }
                    await self.pause(reason: "Interruzione di sistema")
                    self.error = "Registrazione messa in pausa dal sistema. Premi Riprendi quando vuoi continuare."
                }
            }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor in await self?.pause(reason: "Dispositivo audio scollegato") }
            }
    }

    func load() async {
        guard !recording else { return }
        do {
            sessions = try await workspace.catalog().sessions
            for index in sessions.indices where sessions[index].state != "finished" {
                var repaired = sessions[index]
                var start: Double = 0
                var segments: [AudioTimelineSegment] = []
                for original in repaired.segments {
                    var segment = original
                    let url = try await workspace.url(segment.file)
                    if !FileManager.default.fileExists(atPath: url.path), segment.duration == 0 { continue }
                    if let audio = try? AVAudioPlayer(contentsOf: url), audio.duration.isFinite {
                        segment.duration = max(segment.duration, audio.duration)
                    }
                    segment.start = start; start += segment.duration; segments.append(segment)
                }
                repaired.segments = segments; repaired.state = "paused"
                if repaired != sessions[index] {
                    repaired.revision = (repaired.revision ?? 0) + 1
                    try await workspace.saveSession(repaired); sessions[index] = repaired
                }
            }
            // Incomplete sessions remain visible and playable. Never resume the mic implicitly.
            if let pending = sessions.last(where: { $0.state != "finished" }) {
                active = pending; paused = true; elapsed = pending.duration
            }
            if let pending = try await workspace.pendingAudioCompression() { startCompression(pending.sessionID) }
        } catch { self.error = error.localizedDescription }
    }

    func start() async {
        guard !recording, !transitioning, !closed, !suspended, transcribingSessionID == nil, compressionTask == nil, compressingSessionID == nil else { return }
        transitioning = true
        defer { transitioning = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { error = "Abilita il microfono nelle impostazioni per registrare."; return }
        guard !closed, !suspended else { return }
        do {
            stopPlayback()
            let session = AVAudioSession.sharedInstance()
            #if compiler(>=6.2)
            let bluetooth: AVAudioSession.CategoryOptions = .allowBluetoothHFP
            #else
            let bluetooth: AVAudioSession.CategoryOptions = .allowBluetooth
            #endif
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, bluetooth])
            try session.setActive(true)
            if active == nil { active = AudioSession(title: "Registrazione \(sessions.count + 1)") }
            guard var entry = active else { return }
            let file = "audio/\(entry.id)-\(UUID()).caf"
            let url = try await workspace.url(file)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false]
            let audio = try AVAudioRecorder(url: url, settings: settings)
            audio.delegate = self
            guard audio.prepareToRecord() else { throw CocoaError(.fileWriteUnknown) }
            entry.segments.append(AudioTimelineSegment(file: file, start: entry.duration,
                hostStart: ProcessInfo.processInfo.systemUptime))
            entry.state = "recording"
            entry.revision = (entry.revision ?? 0) + 1
            // Persist the file reference before starting the microphone.
            try await workspace.saveSession(entry)
            guard !closed, !suspended else {
                audio.stop(); entry.state = "paused"; entry.revision = (entry.revision ?? 0) + 1
                active = entry; paused = true
                try await workspace.saveSession(entry)
                return
            }
            guard audio.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = audio; active = entry; recording = true; paused = false
            beginTicker()
        } catch { self.error = error.localizedDescription }
    }

    func pause(reason: String = "Pausa") async {
        guard recording, var entry = active, !entry.segments.isEmpty else { return }
        let duration = max(recorder?.currentTime ?? 0, entry.segments[entry.segments.count - 1].duration)
        recorder?.stop(); recorder = nil
        entry.segments[entry.segments.count - 1].duration = duration
        entry.segments[entry.segments.count - 1].endReason = reason
        entry.state = "paused"
        entry.revision = (entry.revision ?? 0) + 1
        active = entry; recording = false; paused = true; elapsed = entry.duration
        _ = await persist(entry)
    }

    /// Snapshot metadata without stopping the recorder or deactivating its session.
    /// The background audio mode keeps AVFoundation active while the screen locks.
    func checkpointRecording() async {
        guard recording, var entry = active, !entry.segments.isEmpty else { return }
        let last = entry.segments.count - 1
        entry.segments[last].duration = max(entry.segments[last].duration, recorder?.currentTime ?? 0)
        entry.revision = (entry.revision ?? 0) + 1
        active = entry; elapsed = entry.duration
        _ = await persist(entry)
    }

    func refreshRecordingAfterForeground() async {
        guard recording else { return }
        if recorder?.isRecording == true { await checkpointRecording() }
        else {
            await pause(reason: "Registrazione interrotta dal sistema")
            error = "Il sistema ha interrotto la registrazione. L’audio già scritto è conservato; premi Riprendi per continuare."
        }
    }

    func finish() async {
        guard !transitioning else { return }
        transitioning = true
        var compressedID: UUID?
        defer { transitioning = false; if let compressedID { startCompression(compressedID) } }
        if recording { await pause(reason: "Fine registrazione") }
        guard var entry = active else { return }
        entry.state = "finished"
        entry.revision = (entry.revision ?? 0) + 1
        guard await persist(entry) else { return }
        active = nil; paused = false
        compressedID = entry.id
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { self.error = error.localizedDescription }
    }

    private func persist(_ entry: AudioSession) async -> Bool {
        do {
            try await workspace.saveSession(entry)
            sessions = try await workspace.catalog().sessions
            return true
        } catch { self.error = "Audio conservato sul dispositivo, ma indice non salvato: \(error.localizedDescription)"; return false }
    }

    func play(_ session: AudioSession, at seconds: Double = 0) async {
        guard compressionTask == nil, compressingSessionID == nil else { error = "Attendi o metti in pausa la compressione prima dell’ascolto."; return }
        guard session.trashedAt == nil else { error = "Ripristina la registrazione dal cestino prima di ascoltarla."; return }
        guard !recording else { error = "Metti in pausa la registrazione prima di riprodurre."; return }
        do {
            stopPlayback()
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback); try audio.setActive(true)
            guard let index = session.segments.firstIndex(where: { seconds < $0.start + $0.duration })
                    ?? session.segments.indices.last else { return }
            playingSessionID = session.id; playingIndex = index
            try await playSegment(session, index: index, offset: max(0, seconds - session.segments[index].start))
            beginTicker()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription; stopPlayback() }
    }

    private func playSegment(_ session: AudioSession, index: Int, offset: Double) async throws {
        let generation = playbackGeneration
        let url = try await workspace.url(session.segments[index].file)
        guard generation == playbackGeneration, playingSessionID == session.id, !recording, !closed else { throw CancellationError() }
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = self; audio.currentTime = offset
        audio.enableRate = true; audio.rate = Float(playbackRate)
        playback = session.segments[index].start + offset
        guard audio.prepareToPlay(), audio.play() else { throw CocoaError(.fileReadCorruptFile) }
        player = audio; playingIndex = index
    }

    func setPlaybackRate(_ rate: Double) {
        guard rate.isFinite, (0.5...2).contains(rate) else { return }
        playbackRate = rate; player?.enableRate = true; player?.rate = Float(rate)
    }

    func organize(_ id: UUID, action: AudioLibraryAction) async {
        guard canTranscribe, transcribingSessionID == nil, active?.id != id, let value = sessions.first(where: { $0.id == id }) else {
            error = "Termina la registrazione o attendi la trascrizione prima di modificare l’archivio."; return
        }
        transitioning = true; defer { transitioning = false }
        do {
            _ = try await workspace.changeAudioSession(id, expectedRevision: value.revision ?? 0, action: action)
            if case .trash = action, playingSessionID == id { stopPlayback() }
            sessions = try await workspace.catalog().sessions
        } catch { self.error = error.localizedDescription }
    }

    func addBookmark(sessionID: UUID? = nil, title: String = "Momento importante") async {
        guard transcribingSessionID == nil else { error = "Attendi il termine della trascrizione per aggiungere un segnalibro."; return }
        let id = sessionID ?? active?.id ?? playingSessionID
        guard let id else { return }
        let entry = active?.id == id ? active : sessions.first { $0.id == id }
        guard var value = entry, (value.bookmarks?.count ?? 0) < 1000 else { return }
        let seconds = active?.id == id ? (recordingAnchor?.1 ?? elapsed) : playingSessionID == id ? playback : 0
        if recording, let last = value.segments.indices.last { value.segments[last].duration = max(value.segments[last].duration, recorder?.currentTime ?? 0) }
        value.bookmarks = (value.bookmarks ?? []) + [AudioBookmark(title: String(title.prefix(120)), seconds: min(value.duration, max(0, seconds)))]
        value.revision = (value.revision ?? 0) + 1
        if active?.id == id { active = value }
        _ = await persist(value)
    }

    func removeBookmark(_ bookmark: AudioBookmark, sessionID: UUID) async {
        guard transcribingSessionID == nil, var value = active?.id == sessionID ? active : sessions.first(where: { $0.id == sessionID }) else { return }
        value.bookmarks?.removeAll { $0.id == bookmark.id }; value.revision = (value.revision ?? 0) + 1
        if active?.id == sessionID { active = value }
        _ = await persist(value)
    }

    func renameBookmark(_ bookmarkID: UUID, sessionID: UUID, title: String) async {
        guard transcribingSessionID == nil, var value = active?.id == sessionID ? active : sessions.first(where: { $0.id == sessionID }),
              let i = value.bookmarks?.firstIndex(where: { $0.id == bookmarkID }) else { return }
        do {
            value.bookmarks?[i].title = try LibraryName.validated(title); value.revision = (value.revision ?? 0) + 1
            if active?.id == sessionID { active = value }; _ = await persist(value)
        } catch { self.error = error.localizedDescription }
    }

    func importAudio(_ source: URL) async {
        guard canTranscribe, transcribingSessionID == nil else { return }
        transitioning = true; defer { transitioning = false }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration).seconds
            let session = try await workspace.importAudio(from: source, duration: duration, title: source.deletingPathExtension().lastPathComponent)
            sessions = try await workspace.catalog().sessions
            transcriptionStatusSessionID = session.id; transcriptionStatus = "Audio importato. Puoi riprodurlo o trascriverlo sul dispositivo."
        } catch { self.error = error.localizedDescription }
    }

    func stopPlayback() { playbackGeneration = UUID(); player?.stop(); player = nil; playingSessionID = nil }

    func skipPlayback(by seconds: Double) async {
        guard seconds.isFinite, let id = playingSessionID, let session = sessions.first(where: { $0.id == id }) else { return }
        let target = min(session.duration, max(0, playback + seconds))
        if target >= session.duration { stopPlayback(); playback = session.duration }
        else { await play(session, at: target) }
    }

    func suspendForTabChange() async {
        suspended = true
        if recording { await pause(reason: "Cambio scheda") }
        stopPlayback()
    }

    func resumeAfterTabChange() { suspended = false }

    private func beginTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var count = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                if self.recording, var entry = self.active, !entry.segments.isEmpty {
                    entry.segments[entry.segments.count - 1].duration = max(
                        entry.segments[entry.segments.count - 1].duration, self.recorder?.currentTime ?? 0)
                    entry.revision = (entry.revision ?? 0) + 1
                    self.active = entry; self.elapsed = entry.duration
                    count += 1
                    if count % 4 == 0 { _ = await self.persist(entry) }
                } else if let id = self.playingSessionID,
                          let entry = self.sessions.first(where: { $0.id == id }),
                          entry.segments.indices.contains(self.playingIndex) {
                    self.playback = entry.segments[self.playingIndex].start + (self.player?.currentTime ?? 0)
                } else { return }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayer = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let currentPlayer = self.player, ObjectIdentifier(currentPlayer) == finishedPlayer, let id = self.playingSessionID,
                  let entry = self.sessions.first(where: { $0.id == id }) else { return }
            let next = self.playingIndex + 1
            guard flag, entry.segments.indices.contains(next) else { self.stopPlayback(); return }
            do { try await self.playSegment(entry, index: next, offset: 0) }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription; self.stopPlayback() }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "Errore durante la registrazione."
        Task { @MainActor [weak self] in
            await self?.pause(reason: "Errore registrazione"); self?.error = message
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor [weak self] in
            await self?.pause(reason: "Registrazione interrotta")
            self?.error = "La registrazione si è interrotta. Controlla lo spazio disponibile prima di riprendere."
        }
    }

    func close() async {
        closed = true
        compressionTask?.cancel(); await compressionTask?.value; compressionTask = nil
        transcriptionTask?.cancel(); await transcriptionTask?.value; transcriptionTask = nil
        if recording { await pause(reason: "Chiusura quaderno") }
        stopPlayback(); ticker?.cancel(); ticker = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        if let routeChange { NotificationCenter.default.removeObserver(routeChange) }
        routeChange = nil
    }
}
