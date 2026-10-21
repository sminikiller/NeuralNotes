import UIKit
import PencilKit
import AVFoundation
import NeuralNotesCore

@MainActor
enum RoadmapDiagnostics {
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
        try require(map.texts.count == 3 && map.shapes?.count == 2 && map.texts[1].pageLink?.pageID == page, "Mappa o fonte non modificabili.")
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
