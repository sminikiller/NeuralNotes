import UIKit
import PencilKit
import AVFoundation
import NeuralNotesCore

@MainActor
enum RoadmapDiagnostics {
    static func audioCompression(root: URL) async throws {
        let writer = try workspace(root: root), path = "audio/compression-check.caf", source = try await writer.url(path)
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
            let file = try AVAudioFile(forWriting: source, settings: settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192), let samples = buffer.floatChannelData?[0] else { throw Failure.assertion("Buffer di controllo non disponibile.") }
            samples.initialize(repeating: 0, count: 8192)
            var remaining = 143325
            while remaining > 0 {
                buffer.frameLength = AVAudioFrameCount(min(8192, remaining)); try file.write(from: buffer); remaining -= Int(buffer.frameLength)
            }
        }
        var entry = AudioSession(title: "Verifica AAC"); entry.state = "finished"
        var part = AudioTimelineSegment(file: path, start: 0, hostStart: 0); part.duration = 3.25; entry.segments = [part]
        try await writer.saveSession(entry)
        let controller = AudioController(workspace: writer); await controller.load()
        controller.startCompression(entry.id); await controller.compressionTask?.value
        let failure = controller.error; await controller.close()
        if let failure { throw Failure.assertion(failure) }
        guard let saved = try await writer.catalog().sessions.first?.segments.first else { throw Failure.assertion("Parte audio non indicizzata.") }
        try require(saved.codec == "aac" && saved.bitRate == 64000 && saved.start == 0 && saved.duration == 3.25, "Tempi o metadati AAC diversi dall’originale.")
        let file = try await writer.url(saved.file)
        var sizes: [UInt32] = []
        let frames = try AudioWindowReader.read(url: file, window: SpeechWindow(start: 3, duration: 0.25), chunk: 1024) { sizes.append($0.frameLength) }
        try require(frames > 0 && !sizes.isEmpty && sizes.allSatisfy { $0 <= 1024 }, "Ultimo blocco AAC non leggibile.")
        try require(!FileManager.default.fileExists(atPath: source.path), "Pulizia PCM non completata.")
        _ = try NativePackageInspector.inspect(writer.package)
    }
    static func backupBudget(root: URL) async throws {
        let writer = try workspace(root: root), manifest = try await writer.manifest()
        let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Budget di controllo", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
        _ = try await writer.addPage()
        var files: [URL] = []
        for _ in 0..<4 {
            if let file = try await writer.createAutomaticBackup(metadata: metadata, minimumInterval: 0, maximumBytes: 1) { files.append(file) }
        }
        let copies = try await writer.automaticBackups()
        let actual = Set(copies.map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path })
        let expected = Set(files.suffix(2).map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        try require(copies.count == 2 && actual == expected, "Le ultime due copie non sono state protette.")
        try require(AutomaticBackupPolicy.budget(copyBytes: 1) == 64 << 20 && AutomaticBackupPolicy.budget(copyBytes: Int64.max) == 1 << 30, "Limite backup non corretto.")
    }
    static func audioExportAndOrganization(root: URL) async throws {
        let writer = try workspace(root: root), file = "audio/check.caf", destination = try await writer.url(file)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        do {
            let audio = try AVAudioFile(forWriting: destination, settings: settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 16000), let channels = buffer.floatChannelData else { throw Failure.assertion("Buffer audio non disponibile.") }
            buffer.frameLength = 16000; channels[0].initialize(repeating: 0, count: 16000); try audio.write(from: buffer)
        }
        try require(abs(try AudioWindowReader.duration(of: destination) - 1) < 0.001, "Il file audio di controllo non è leggibile.")
        var session = AudioSession(title: "Controllo export"); session.state = "finished"; session.revision = 1
        var segment = AudioTimelineSegment(file: file, start: 0, hostStart: 0); segment.duration = 1; session.segments = [segment]
        session.transcript = [TranscriptSegment(start: 0, duration: 1, text: "Testo di controllo")]; session.transcriptionComplete = true
        try await writer.saveSession(session)
        let bundle = try await writer.exportAudioSession(session.id); defer { try? bundle.removeTemporaryFiles() }
        guard let copied = bundle.files.first(where: { $0.pathExtension == "caf" }) else { throw Failure.assertion("File audio non esportato.") }
        try require(Data(contentsOf: copied) == Data(contentsOf: destination), "I byte dell’audio esportato sono diversi.")
        var changed = try await writer.changeAudioSession(session.id, expectedRevision: 1, action: .trash)
        changed = try await writer.changeAudioSession(changed.id, expectedRevision: changed.revision!, action: .restore)
        try require(changed.trashedAt == nil && changed.hasTranscriptText && FileManager.default.fileExists(atPath: destination.path), "Ripristino audio non completo.")
    }
    static func lensAndWebLinks() throws {
        let area = LensGeometry.selection(from: StrokeSample(x: 20, y: 100), to: StrokeSample(x: 120, y: 100), pageWidth: 768, pageHeight: 1024)
        try require(area != nil && area!.minY < 100, "La sottolineatura non comprende il testo superiore.")
        let circle = [StrokeSample(x: 10, y: 50), StrokeSample(x: 50, y: 10), StrokeSample(x: 90, y: 50), StrokeSample(x: 50, y: 90), StrokeSample(x: 10, y: 50)]
        try require(LensGeometry.selection(trace: circle, pageWidth: 768, pageHeight: 1024)?.width == 80, "La selezione cerchiata si è ridotta ai soli estremi.")
        let source = WebSource(title: "Fonte di controllo", url: "https://example.com", endIndex: 4)
        let artifact = AIArtifact(text: "Dato", references: [], provider: "Controllo locale, senza rete", webSources: [source])
        _ = try artifact.validatedWebResearch()
        try require(artifact.citedRuns.contains(where: { $0.link == source.link }) && !WebSource(title: "No", url: "javascript:x").isValid, "Collegamenti non validati.")
    }
    private enum Failure: LocalizedError {
        case assertion(String)
        var errorDescription: String? { switch self { case .assertion(let message): return message } }
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }
    private static func workspace(root: URL) throws -> DocumentWorkspace {
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        return DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
    }
    static func pageBatch(root: URL) async throws {
        let writer = try workspace(root: root)
        var first = PageSnapshot(); first.texts = [TextElement(text: "Da trasferire")]
        first = try await writer.addPage(first); let second = try await writer.addPage()
        var empty = first, destination = second; destination.texts = empty.texts; empty.texts = []
        let bytes = PKDrawing().dataRepresentation()
        _ = try await writer.applyPageBatch([PageMutation(page: empty, expectedRevision: 0, drawing: bytes), PageMutation(page: destination, expectedRevision: 0, drawing: bytes)])
        let pages = try await writer.pages()
        try require(pages.count == 2 && pages[0].texts.isEmpty && pages[1].texts.first?.text == "Da trasferire", "Spostamento tra pagine non completo.")
        do {
            try await writer.applyPageBatch([PageMutation(page: first, expectedRevision: 0, drawing: bytes), PageMutation(page: second, expectedRevision: 0, drawing: bytes)])
            throw Failure.assertion("Una revisione obsoleta ha sostituito la pagina.")
        } catch WorkspaceFailure.staleRevision { }
        _ = try NativePackageInspector.inspect(writer.package)
    }
    static func quiz(root: URL) async throws {
        let writer = try workspace(root: root), page = try await writer.addPage()
        let reference = SourceReference(documentID: writer.documentID, pageID: page.id)
        let cards = (1...5).map { StudyCard(question: "Domanda \($0)", answer: "Risposta \($0)", source: reference) }
        guard let bank = QuizBuilder.make(cards: cards, seed: 42) else { throw Failure.assertion("Quiz locale non creato.") }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var run = try await writer.startQuiz(bank, mode: .exam, minutes: 1, now: now)
        try run.choose(bank.questions[0].correctIndex, question: 0, now: now.addingTimeInterval(2))
        try await writer.saveQuiz(run)
        let saved = try await writer.catalog().activeQuiz
        try require(saved?.answers == run.answers && run.expired(at: now.addingTimeInterval(61)), "Risposta o scadenza non conservate.")
        try run.submit(now: now.addingTimeInterval(61)); try await writer.saveQuiz(run)
        let catalog = try await writer.catalog()
        try require(catalog.activeQuiz == nil && catalog.quizHistory?.last?.score == 1, "Risultato del quiz non conservato.")
    }
    static func sourcesAndMaps() throws {
        let document = UUID(), page = UUID()
        let chunks = (0..<180).map { IndexedChunk(text: "Argomento al minuto \($0)", reference: SourceReference(documentID: document, seconds: Double($0 * 60)), kind: .audio) }
        let context = SourceContext.select(chunks, spread: true)
        try require(context.wasTruncated && context.sources.count == 40 && context.sources.last?.reference.seconds == 179 * 60,
                    "Il contesto della lezione esclude la parte finale.")
        let source = SourceReference(documentID: document, pageID: page)
        let artifact = AIArtifact(text: "Lezione\nPrimo concetto [1]\nSecondo concetto", references: [source], provider: "Controllo locale", task: .outline)
        guard let map = MindMapLayout.page(from: artifact) else { throw Failure.assertion("Mappa non creata.") }
        let nodes = map.shapes ?? [], edges = map.connectors ?? []
        try require(nodes.count == 3 && edges.count == 2 && nodes[0].label == "Lezione" &&
                    nodes[1].pageLink?.pageID == page && nodes[1].pageLink?.documentID == document,
                    "Mappa o fonte non modificabili.")
        try require(edges.allSatisfy { edge in
            edge.from.objectID == nodes[0].id && nodes.dropFirst().contains { $0.id == edge.to.objectID }
        }, "Collegamenti della mappa non agganciati ai blocchi.")
        try PageValidation.validate(map)
    }
    static func editor(root: URL) async throws {
        let model = EditorViewModel(workspace: try workspace(root: root)); await model.open()
        do {
            let points = [CGPoint(x: 30, y: 40), CGPoint(x: 120, y: 70)].enumerated().map { i, point in
                PKStrokePoint(location: point, timeOffset: Double(i) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            model.editText([TextElement(text: "Quantità da conservare")]); model.strokeBegan()
            model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
            model.strokeEnded(); model.finishInkGesture(); model.selectAll()
            model.cutSelection(maximumBytes: 1)
            try require(model.page?.texts.count == 1 && model.canvas.drawing.strokes.count == 1, "Taglia ha eliminato una selezione non copiata.")
            model.error = nil
            let origin = model.page; await model.addPage()
            guard let destination = model.page?.id, let origin else { throw LibraryFailure.missingItem }
            await model.select(origin); model.selectAll(); await model.moveSelection(to: destination)
            try require(model.page?.id == destination && model.page?.texts.count == 1 && model.canvas.drawing.strokes.count == 1, "Selezione non trasferita.")
            await model.performUndo()
            try require(model.page?.id == origin.id && model.canvas.drawing.strokes.count == 1, "Undo dello spostamento non completo.")
            let ink = model.canvas.drawing.dataRepresentation(); model.setLaserActive(true)
            try require(model.laserActive && model.canvas.drawing.dataRepresentation() == ink, "Il laser modifica l’inchiostro.")
            model.setLaserActive(false)
            guard let text = model.page?.texts.first else { throw LibraryFailure.missingItem }
            try require(!RichText.matchingRects("quantita", in: text, pageHeight: origin.height).isEmpty, "Testo non localizzato sul foglio.")
            let closed = await model.close(); try require(closed, "Chiusura del documento temporaneo fallita.")
        } catch { _ = await model.close(); throw error }
    }
}
