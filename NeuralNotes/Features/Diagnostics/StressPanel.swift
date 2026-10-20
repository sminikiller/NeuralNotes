import SwiftUI
import PencilKit
import AVFoundation
import PDFKit
import NeuralNotesCore

@MainActor
struct StressPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var progress = 0.0
    @State private var status = "Prova facoltativa su dati temporanei: 50 pagine scritte, audio sintetico di 60 secondi, export PDF vettoriale e backup/reimport. Non accende il microfono e non tocca i tuoi quaderni."
    @State private var job: Task<Void, Never>?

    private func fixtureDrawing() -> Data {
        var points: [PKStrokePoint] = []
        points.reserveCapacity(120)
        let pointSize = CGSize(width: 4.0, height: 4.0)
        let altitude: CGFloat = CGFloat.pi / 2.0
        for index in 0..<120 {
            let sample: Double = Double(index)
            let phase: Double = sample * 0.2
            let wave: Double = sin(phase) * 50.0
            let x: CGFloat = CGFloat(40.0 + sample * 5.0)
            let y: CGFloat = CGFloat(160.0 + wave)
            let location = CGPoint(x: x, y: y)
            let offset: TimeInterval = sample / 120.0
            let point = PKStrokePoint(location: location, timeOffset: offset, size: pointSize,
                opacity: 1.0, force: 1.0, azimuth: 0.0, altitude: altitude)
            points.append(point)
        }
        let ink = PKInk(.pen, color: .black)
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        let drawing = PKDrawing(strokes: [stroke])
        return drawing.dataRepresentation()
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(status).textSelection(.enabled)
                if busy { ProgressView(value: progress) }
                Button(busy ? "Interrompi prova" : "Avvia prova di carico", systemImage: busy ? "stop.circle" : "speedometer") {
                    if busy { job?.cancel() } else { job = Task { await run() } }
                }
            }
            .navigationTitle("Carico e integrità")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { job?.cancel(); dismiss() } } }
            .onDisappear { job?.cancel() }
        }
    }
    private func run() async {
        busy = true; progress = 0
        defer { busy = false }
        let started = Date()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NN-stress-\(UUID())")
        var archiveDirectory: URL?, pdfURL: URL?
        defer {
            try? FileManager.default.removeItem(at: root)
            if let archiveDirectory { try? FileManager.default.removeItem(at: archiveDirectory) }
            if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
        }
        do {
            let store = try NativeDocumentStore(root: root)
            let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
            let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
            let bytes: Data = fixtureDrawing()
            for index in 0..<50 {
                try Task.checkCancellation()
                var page = try await workspace.addPage(); page.revision = 1
                page.texts = [TextElement(text: "Pagina di controllo \(index + 1)")]
                _ = try await workspace.save(page, drawing: bytes)
                progress = Double(index + 1) / 100; status = "Pagine scritte e salvate: \(index + 1)/50"
            }
            var session = AudioSession(title: "Audio sintetico di controllo")
            let relative = "audio/\(UUID()).caf", audioURL = try await workspace.url(relative)
            status = "Creazione audio CAF sintetico di 60 secondi…"
            let audioJob: Task<Void, Error> = Task.detached(priority: .utility) {
                let file = try AVAudioFile(forWriting: audioURL, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100),
                      let samples = buffer.floatChannelData else { throw CocoaError(.fileWriteUnknown) }
                buffer.frameLength = 44100; samples[0].initialize(repeating: 0, count: 44100)
                for _ in 0..<60 { try Task.checkCancellation(); try file.write(from: buffer) }
            }
            try await withTaskCancellationHandler { try await audioJob.value } onCancel: { audioJob.cancel() }
            var segment = AudioTimelineSegment(file: relative, start: 0, hostStart: 0); segment.duration = 60
            session.segments = [segment]; session.state = "finished"; try await workspace.saveSession(session)
            progress = 0.65; status = "Esportazione PDF vettoriale…"
            let pdf = try await DocumentServices.exportPDF(workspace: workspace); pdfURL = pdf
            guard PDFDocument(url: pdf)?.pageCount == 50 else { throw LibraryFailure.corruptDocument }
            let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Carico temporaneo",
                createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
            progress = 0.75; status = "Backup e reimportazione di pagine e audio…"
            let archive = try await workspace.exportNative(metadata: metadata); archiveDirectory = archive.deletingLastPathComponent()
            let id = UUID(), book = UUID()
            let importJob = Task.detached(priority: .utility) { try NativeImport.copy(from: archive, into: store, documentID: id, notebookID: book) }
            _ = try await withTaskCancellationHandler { try await importJob.value } onCancel: { importJob.cancel() }
            let restored = DocumentWorkspace(package: store.packageURL(for: id), documentID: id, notebookID: book)
            let pages = try await restored.pages(), catalog = try await restored.catalog()
            guard pages.count == 50, let page = pages.last,
                  let audio = catalog.sessions.first?.segments.first else { throw LibraryFailure.corruptDocument }
            let restoredDrawing: Data? = try await restored.drawing(page)
            guard restoredDrawing == bytes else { throw LibraryFailure.corruptDocument }
            let restoredAudioURL: URL = try await restored.url(audio.file)
            let restoredAudio = try AVAudioFile(forReading: restoredAudioURL)
            guard restoredAudio.length == 44100 * 60 else { throw LibraryFailure.corruptDocument }
            let storage = try await restored.storageReport()
            progress = 1; status = "PASS · 50 pagine, PDF vettoriale, CAF sintetico 60 s e backup riaperti. \(ByteCountFormatter.string(fromByteCount: storage.totalBytes, countStyle: .file)) · \(Int(Date().timeIntervalSince(started))) s. Questa prova non misura registrazioni reali, latenza Pencil o memoria di picco."
        } catch is CancellationError { status = "Prova interrotta. I dati temporanei vengono rimossi." }
        catch { status = "FAIL · \(error.localizedDescription)" }
    }
}
