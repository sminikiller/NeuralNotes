import SwiftUI
import SwiftData
import PencilKit
import PDFKit
import AVFoundation
import NeuralNotesCore

private struct DiagnosticResult: Identifiable {
    let id = UUID()
    let title: String
    let passed: Bool
    let detail: String
}

private enum DiagnosticFailure: LocalizedError {
    case assertion(String)
    var errorDescription: String? {
        switch self { case .assertion(let message): return message }
    }
}

@MainActor
struct DiagnosticsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiagnosticResult] = []
    @State private var running = false
    @State private var stress = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Questi controlli usano documenti temporanei separati dai tuoi quaderni. Non richiedono microfono, account o collegamenti AI.")
                    Button(running ? "Verifica in corso…" : "Esegui controlli sul mio iPad", systemImage: "checkmark.seal") {
                        Task { await run() }
                    }.disabled(running)
                    if running { ProgressView() }
                    Button("Prova di carico facoltativa", systemImage: "speedometer") { stress = true }.disabled(running)
                }
                Section {
                    DisclosureGroup("Ambiente di esecuzione") {
                        LabeledContent("Sistema", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        LabeledContent("Versione app", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Non esposta dal runner")
                        LabeledContent("SDK dichiarato", value: Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "Non esposto dal runner")
                        #if compiler(>=6.2)
                        Text("Compilatore Swift 6.2 o successivo")
                        #elseif compiler(>=6.0)
                        Text("Compilatore Swift 6.0–6.1")
                        #else
                        Text("Compilatore Swift precedente alla 6.0")
                        #endif
                        #if canImport(FoundationModels)
                        Text("FoundationModels presente nell’SDK")
                        #else
                        Text("FoundationModels assente nell’SDK")
                        #endif
                        #if canImport(PaperKit)
                        Text("PaperKit presente nell’SDK")
                        #else
                        Text("PaperKit assente nell’SDK")
                        #endif
                        Text("La presenza di un modulo nell’SDK non conferma il supporto del sistema, dei modelli installati o dell’hardware.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Registro delle trascrizioni") {
                        Text("Ultimi blocchi elaborati sul dispositivo: metodo, tempo, caratteri, memoria libera ed eventuale errore.")
                            .font(.caption).foregroundStyle(.secondary)
                        TranscriptionLogView(limit: 40)
                    }
                }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(result.title, systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                        Text(result.detail).font(.caption).textSelection(.enabled)
                    }
                }
                if !results.isEmpty {
                    Section {
                        ShareLink("Condividi risultati", item: results.map { "\($0.passed ? "PASS" : "FAIL") — \($0.title): \($0.detail)" }.joined(separator: "\n"))
                    }
                }
            }
            .navigationTitle("Verifica sul dispositivo")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() }.disabled(running) } }
            .interactiveDismissDisabled(running)
            .sheet(isPresented: $stress) { StressPanel() }
        }
    }

    private func check(_ title: String, _ work: () async throws -> Void) async {
        do {
            try await work(); results.append(DiagnosticResult(title: title, passed: true, detail: "Completato sul dispositivo."))
        } catch {
            results.append(DiagnosticResult(title: title, passed: false, detail: error.localizedDescription))
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw DiagnosticFailure.assertion(message) }
    }

    private func run() async {
        running = true; results = []
        defer { running = false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralNotes-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let store = try NativeDocumentStore(root: root.appendingPathComponent("Notebooks"))
            let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
            try store.create(manifest)
            let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
                documentID: manifest.documentID, notebookID: manifest.notebookID)
            var saved: PageSnapshot?
            await check("Catalogo: recupero conserva originali e media") {
                let recoveryStore = try NativeDocumentStore(root: root.appendingPathComponent("CatalogRecovery"))
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID()); try recoveryStore.create(index)
                let writer = DocumentWorkspace(package: recoveryStore.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID)
                _ = try await writer.addPage()
                let settings = NotebookWorkspaces.starter()
                try await writer.setEditorWorkspaces(settings); try await writer.setCoverAppearance(image: nil, design: CoverDesign())
                let catalog = try await writer.url("catalog.json"), media = try await writer.url("audio/retained.caf")
                let broken = Data("interrupted catalog".utf8), bytes = Data([7, 8, 9])
                try bytes.write(to: media); try broken.write(to: catalog)
                try await writer.restorePreviousCatalog()
                let reopened = try await writer.catalog()
                _ = try await writer.cleanUnusedFiles()
                let recoveryURL = try await writer.url("recovery")
                let files = try FileManager.default.contentsOfDirectory(at: recoveryURL, includingPropertiesForKeys: nil)
                let original = files.first { $0.lastPathComponent.hasPrefix("catalog-interrupted-") }
                let retainedBytes = try Data(contentsOf: media)
                try require(reopened.editorWorkspaces == settings && retainedBytes == bytes, "Catalogo o media non conservati.")
                guard let original else { throw DiagnosticFailure.assertion("Catalogo originale non conservato.") }
                let originalBytes = try Data(contentsOf: original)
                try require(originalBytes == broken, "I byte originali del catalogo differiscono.")
            }
            await check("Workspace: configurazioni indipendenti e riapertura") {
                var settings = NotebookWorkspaces.starter()
                let first = settings.profiles[0]
                settings.profiles[1].dock = .leading; settings.profiles[1].favorites = [.pen, .ruler, .line]
                settings.selectedID = settings.profiles[1].id
                try await workspace.setEditorWorkspaces(settings)
                let reopened = try await workspace.catalog()
                try require(reopened.editorWorkspaces == settings && settings.profiles[0] == first, "Le configurazioni non restano indipendenti.")
            }
            await check("Forme: frecce direzionali e compatibilità dei dati") {
                guard let arrow = ShapeElement.dragged(kind: .arrow, from: StrokeSample(x: 300, y: 240), to: StrokeSample(x: 40, y: 60), color: .blue, lineWidth: 3) else {
                    throw DiagnosticFailure.assertion("Freccia non creata.")
                }
                let copy = try JSONDecoder().decode(ShapeElement.self, from: JSONEncoder().encode(arrow))
                try require(copy.start == ShapeEndpoint(x: 1, y: 1) && copy.end == ShapeEndpoint(x: 0, y: 0), "La direzione della freccia non è conservata.")
            }
            await check("Precisione: riconoscimento di linea e cerchio") {
                let line = (0...20).map { StrokeSample(x: Double($0) * 6, y: 40 + sin(Double($0))) }
                let circle = (0...80).map { i -> StrokeSample in
                    let angle = Double(i) * .pi * 2 / 80
                    return StrokeSample(x: 100 + cos(angle) * 60, y: 100 + sin(angle) * 50)
                }
                try require(HeldShapeRecognition.recognize(line) == .line && HeldShapeRecognition.recognize(circle) == .ellipse, "Geometria non riconosciuta.")
            }
            await check("Colori dell’inchiostro: carta chiara anche in dark mode") {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    let canvas = PKCanvasView()
                    let host = CanvasHost(canvas: canvas)
                    host.overrideUserInterfaceStyle = style
                    // Effective traits of an off-window UIView can stay unspecified until
                    // UIKit attaches it. Check the declared override, then rendered pixels.
                    try require(canvas.overrideUserInterfaceStyle == .light && host.surface.overrideUserInterfaceStyle == .light,
                        "Carta o canvas non impostati in modalità chiara.")
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    let validBlack = PaperInk.color(.black).getRed(&r, green: &g, blue: &b, alpha: &a)
                    try require(validBlack && max(r, max(g, b)) < 0.01, "La penna nera non mantiene il nero.")
                    let validWhite = PaperInk.color(.white).getRed(&r, green: &g, blue: &b, alpha: &a)
                    try require(validWhite && min(r, min(g, b)) > 0.99, "La penna bianca non mantiene il bianco.")
                    let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
                    let points = [CGPoint(x: 8, y: 32), CGPoint(x: 56, y: 32)].enumerated().map { index, point in
                        PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                            size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }
                    var luminance: [Double] = []
                    for color in [Color.black, .white] {
                        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: PaperInk.color(color)),
                            path: PKStrokePath(controlPoints: points, creationDate: Date()))])
                        var rendered = UIImage()
                        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                            rendered = UIGraphicsImageRenderer(bounds: rect, format: format).image { result in
                                UIColor.white.setFill(); result.fill(rect)
                                PaperInk.image(drawing, from: rect, scale: 1).draw(in: rect)
                            }
                        }
                        guard let cgImage = rendered.cgImage else { throw LibraryFailure.corruptDocument }
                        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
                        let didRender = pixels.withUnsafeMutableBytes { bytes -> Bool in
                            guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
                                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                            context.draw(cgImage, in: rect); return true
                        }
                        try require(didRender, "Impossibile leggere i pixel di controllo.")
                        let center = (32 * 64 + 32) * 4
                        luminance.append(Double(Int(pixels[center]) + Int(pixels[center + 1]) + Int(pixels[center + 2])) / 765)
                    }
                    try require(luminance[0] < 0.25 && luminance[1] > 0.9,
                        "Pixel in \(style == .dark ? "dark" : "light") mode: nero \(luminance[0]), bianco \(luminance[1]).")
                }
            }
            await check("PencilKit: salvataggio e riapertura dei vettori") {
                let points = [CGPoint(x: 30, y: 40), CGPoint(x: 120, y: 90), CGPoint(x: 220, y: 40)].enumerated().map { index, location in
                    PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                        size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
                let drawing = PKDrawing(strokes: [stroke])
                var page = try await workspace.addPage(); page.revision = 1; page.paper = .grid
                saved = try await workspace.save(page, drawing: drawing.dataRepresentation())
                let reopened = DocumentWorkspace(package: workspace.package, documentID: manifest.documentID, notebookID: manifest.notebookID)
                let pages = try await reopened.pages()
                guard let first = pages.first, let bytes = try await reopened.drawing(first) else { throw LibraryFailure.corruptDocument }
                let restored = try PKDrawing(data: bytes)
                try require(restored.strokes.count == 1 && restored.bounds == drawing.bounds, "I tratti riaperti differiscono dall’originale.")
            }
            await check("Duplicazione pagina e identità indipendenti") {
                guard let saved else { throw DiagnosticFailure.assertion("La prova dipende dal salvataggio dei vettori precedente: correggere prima quell’errore.") }
                let copy = try await workspace.duplicatePage(saved.id)
                try require(copy.id != saved.id, "UUID di pagina riutilizzato.")
                let original = try await workspace.drawing(saved), copied = try await workspace.drawing(copy)
                try require(original == copied, "Contenuto della copia differente.")
            }
            await check("Protezione dei percorsi del documento") {
                let directory = workspace.package
                for isDirectory in [false, true] {
                    let variant = DocumentWorkspace(package: URL(fileURLWithPath: directory.path, isDirectory: isDirectory),
                        documentID: manifest.documentID, notebookID: manifest.notebookID)
                    let file = try await variant.url("drawings/path-check-\(isDirectory).drawing")
                    try Data([1, 2, 3]).write(to: file, options: .atomic)
                    try require(Data(contentsOf: file) == Data([1, 2, 3]), "Un percorso interno valido è stato rifiutato.")
                }
                do { _ = try await workspace.url("../Library.store"); throw DiagnosticFailure.assertion("Percorso esterno accettato.") }
                catch WorkspaceFailure.invalidPath { }
            }
            await check("Pagine: titoli, segnalibri e ordine persistenti") {
                let pages = try await workspace.pages()
                guard let first = pages.first, let last = pages.last else { throw LibraryFailure.missingItem }
                _ = try await workspace.setPageDetails(first.id, title: "Pagina importante", bookmarked: true)
                try await workspace.reorderPages(Array(pages.map(\.id).reversed()))
                let restored = try await workspace.pages()
                try require(restored.first?.id == last.id && restored.last?.title == "Pagina importante"
                    && restored.last?.isBookmarked == true, "Titolo, segnalibro o ordine non conservati.")
                try await workspace.reorderPages(pages.map(\.id))
            }
            await check("PDF ruotato: importazione, originale integro, export") {
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
                let data = renderer.pdfData { result in
                    result.beginPage()
                    ("NeuralNotes PDF test" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
                }
                guard let pdf = PDFDocument(data: data), let source = pdf.page(at: 0) else { throw LibraryFailure.corruptDocument }
                source.rotation = 90
                let url = root.appendingPathComponent("source.pdf")
                guard pdf.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
                let before = try Data(contentsOf: url)
                let imported = try await DocumentServices.importPDF(from: url, into: workspace)
                try require(imported.count == 1 && imported[0].width == 792 && imported[0].height == 612, "Dimensioni della pagina ruotata errate.")
                let after = try Data(contentsOf: url)
                try require(before == after, "Il PDF originale è stato modificato.")
                let output = try await DocumentServices.exportPDF(workspace: workspace)
                defer { try? FileManager.default.removeItem(at: output) }
                let count = try await workspace.pages().count
                try require(PDFDocument(url: output)?.pageCount == count, "Export con numero di pagine errato.")
            }
            await check("OCR Vision su testo di controllo") {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 160)).image { result in
                    UIColor.white.setFill(); result.fill(CGRect(x: 0, y: 0, width: 900, height: 160))
                    ("NEURALNOTES TEST 123" as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.black])
                }
                guard let data = image.pngData() else { throw LibraryFailure.corruptDocument }
                let recognized = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: " ")
                try require(recognized.localizedCaseInsensitiveContains("NEURALNOTES"), "Testo di controllo non riconosciuto: \(recognized)")
            }
            await check("Backup completo: esportazione, importazione e nuova identità") {
                let metadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Backup di controllo",
                    createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
                let file: URL
                do { file = try await workspace.exportNative(metadata: metadata) }
                catch { throw DiagnosticFailure.assertion("Esportazione del backup: \(error.localizedDescription)") }
                defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                let id = UUID(), notebookID = UUID()
                let source = try await workspace.pages()
                do {
                    _ = try await Task.detached {
                        try NativeImport.copy(from: file, into: store, documentID: id, notebookID: notebookID)
                    }.value
                } catch { throw DiagnosticFailure.assertion("Importazione del backup: \(error.localizedDescription)") }
                let copy = DocumentWorkspace(package: store.packageURL(for: id), documentID: id, notebookID: notebookID)
                let restored = try await copy.pages()
                try require(restored.count == source.count && Set(restored.map(\.id)).isDisjoint(with: source.map(\.id)), "Pagine o identità del backup errate.")
                if let first = restored.first, let original = source.first {
                    let a = try await workspace.drawing(original), b = try await copy.drawing(first)
                    try require(a == b, "I vettori del backup differiscono dall’originale.")
                }
            }
            await check("Sintesi locale: riferimenti alle fonti") {
                let reference = SourceReference(documentID: manifest.documentID, pageID: saved?.id)
                let result = try await ExtractiveStudyProvider().generate(AIRequest(task: .summarize, question: "",
                    sources: [IndexedChunk(text: "La fotosintesi converte l’energia luminosa in energia chimica attraverso reazioni cellulari.", reference: reference)]))
                try require(result.references == [reference] && result.text.contains("fotosintesi"), "Sintesi senza riferimento valido.")
            }
            await check("Modello audio: segmenti, pause e anchor persistenti") {
                var session = AudioSession(title: "Timeline di controllo")
                var first = AudioTimelineSegment(file: "audio/test1.caf", start: 0, hostStart: 100); first.duration = 5
                var second = AudioTimelineSegment(file: "audio/test2.caf", start: 5, hostStart: 120); second.duration = 9
                session.segments = [first, second]; session.state = "finished"
                try await workspace.saveSession(session)
                let restored = try await workspace.catalog().sessions.first { $0.id == session.id }
                try require(restored?.duration == 14, "La pausa è stata sommata alla durata dei campioni.")
            }
            await check("Flashcard: risposta, pianificazione e riapertura") {
                let reference = SourceReference(documentID: manifest.documentID, pageID: saved?.id)
                let cards = StudyCardBuilder.make(from: [IndexedChunk(text: "La fotosintesi converte energia luminosa in energia chimica nelle cellule vegetali.", reference: reference)])
                guard let card = cards.first else { throw DiagnosticFailure.assertion("Nessun esercizio creato dalla fonte.") }
                try await workspace.addStudyCards(cards)
                try await workspace.reviewCard(card.id, rating: .good)
                let reopened = DocumentWorkspace(package: workspace.package, documentID: manifest.documentID, notebookID: manifest.notebookID)
                let restored = try await reopened.catalog().studyCards?.first
                try require(restored?.reviewCount == 1 && restored?.intervalDays == 1 && restored?.source == reference,
                    "Progressi o riferimento della flashcard non conservati.")
            }
            await check("SwiftData: rinomina, riapertura e cestino") {
                let schema = Schema(versionedSchema: LibrarySchemaV1.self)
                let config = ModelConfiguration("Diagnostic", schema: schema, url: root.appendingPathComponent("Test.store"), cloudKitDatabase: .none)
                var repo: SwiftDataLibraryRepository? = SwiftDataLibraryRepository(container: try ModelContainer(for: schema,
                    migrationPlan: LibraryMigrationPlan.self, configurations: [config]), documents: store)
                guard let created = try repo?.createNotebook(title: "Controllo", folderID: nil, cover: .lagoon) else { throw LibraryFailure.missingItem }
                try repo?.updateNotebook(id: created.id, title: "Rinominato", folderID: nil, cover: .sand)
                try repo?.deleteNotebook(id: created.id)
                repo = nil
                let reopened = SwiftDataLibraryRepository(container: try ModelContainer(for: schema,
                    migrationPlan: LibraryMigrationPlan.self, configurations: [config]), documents: store)
                try require(reopened.trashedNotebooks().contains { $0.id == created.id && $0.title == "Rinominato" }, "Cestino non persistito.")
                try reopened.restoreNotebook(id: created.id)
                try require(reopened.notebooks().contains { $0.id == created.id }, "Ripristino non riuscito.")
            }
            await check("Editor: undo di testo, forme e pagine") {
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(index)
                let editor = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID))
                await editor.open()
                do {
                    editor.addText(); editor.addShape(.ellipse)
                    await editor.performUndo(); try require(editor.page?.shapes?.isEmpty ?? true, "La forma non è stata annullata.")
                    await editor.performRedo(); try require(editor.page?.shapes?.count == 1, "La forma non è stata ripristinata.")
                    await editor.addPage(); await editor.performUndo()
                    try require(editor.pages.count == 1 && editor.page?.texts.count == 1, "Undo della pagina non conserva il testo.")
                    _ = await editor.close()
                } catch { _ = await editor.close(); throw error }
            }
            await check("Concorrenza: un solo editor scrive nel quaderno") {
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(index)
                let workspace = DocumentWorkspace(package: store.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID)
                let a = EditorViewModel(workspace: workspace), b = EditorViewModel(workspace: workspace)
                await a.open(); await b.open()
                let protected = a.hasLease && !b.hasLease
                _ = await a.close(); await b.open(); let released = b.hasLease; _ = await b.close()
                try require(protected && released, "Il blocco degli editor non protegge il documento o non viene rilasciato.")
            }
            await check("Recupero dell’indice precedente dopo un’interruzione") {
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(index)
                let workspace = DocumentWorkspace(package: store.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID)
                let first = try await workspace.addPage(); _ = try await workspace.addPage()
                let header = try await workspace.url("manifest.json"); try Data("interruzione simulata".utf8).write(to: header)
                try store.restorePreviousManifest(documentID: index.documentID, notebookID: index.notebookID)
                let restored = try await workspace.pages()
                try require(restored.map(\.id) == [first.id], "Indice precedente non ripristinato.")
            }
            await check("Spazio: pulizia senza perdere pagine recuperabili") {
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(index)
                let workspace = DocumentWorkspace(package: store.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID)
                var page = try await workspace.addPage(); page.revision = 1
                page = try await workspace.save(page, drawing: Data([1, 2, 3])); try await workspace.deletePage(page.id)
                let extra = try await workspace.url("images/unused.png"); try Data([42]).write(to: extra)
                _ = try await workspace.cleanUnusedFiles(); try await workspace.restoreRemovedPage(page.id)
                let restored = try await workspace.drawing(page)
                try require(restored == Data([1, 2, 3]) && !FileManager.default.fileExists(atPath: extra.path), "Pulizia o recupero errati.")
            }
            await check("PDF dalla libreria: nuovo quaderno annotabile") {
                let schema = Schema(versionedSchema: LibrarySchemaV1.self)
                let config = ModelConfiguration("PDFCheck", schema: schema, url: root.appendingPathComponent("PDFCheck.store"), cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [config])
                let repository = SwiftDataLibraryRepository(container: container, documents: store)
                let url = root.appendingPathComponent("Nuovo quaderno.pdf")
                let original = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { pdf in pdf.beginPage() }
                try original.write(to: url)
                let notebook = try await repository.importNotebook(from: url, folderID: nil)
                let writer = try repository.workspace(id: notebook.id)
                let pages = try await writer.pages()
                try require(pages.count == 1 && pages[0].pdfFile != nil, "PDF non trasformato in quaderno.")
                try require(Data(contentsOf: url) == original, "Il sorgente PDF è cambiato.")
            }
            await check("Modello quaderno: carta, colore e nuove pagine") {
                let index = DocumentManifest(documentID: UUID(), notebookID: UUID())
                let template = PageTemplate(paper: .grid, appearance: PaperAppearance(tone: .cream, spacing: 28), format: .a4)
                try store.create(index, template: template)
                let writer = DocumentWorkspace(package: store.packageURL(for: index.documentID), documentID: index.documentID, notebookID: index.notebookID)
                let page = try await writer.addDefaultPage()
                try require(page.paper == .grid && page.appearance?.tone == .cream && page.width == template.format.size.width, "Modello della nuova pagina errato.")
            }
            await check("Trascrizione: export per minuto e correzioni") {
                let raw = [TranscriptSegment(start: 1, duration: 1, text: "errato"), TranscriptSegment(start: 65, duration: 1, text: "secondo minuto")]
                let corrected = TranscriptText.corrected(raw, corrections: [TranscriptCorrection(start: 0, text: "corretto")])
                let exported = TranscriptText.export(title: "Lezione", segments: corrected, complete: true)
                try require(exported.contains("[00:00:00] corretto") && exported.contains("[00:01:00] secondo minuto"), "Timestamp o correzioni non conservati nell’export.")
            }
            await check("Zoom pagina intera e cancellazione locale dell’inchiostro") { try verifyCanvasGeometry() }
            await check("Trascrizioni: recupero del testo e risultato vuoto distinguibili") { try verifyReadableTranscript() }
            await check("Audio: lettura diretta dei blocchi, senza conversione") {
                let url = root.appendingPathComponent("blocchi.caf")
                try writeSilence(url, seconds: 100, rate: 16000)
                let duration = try AudioWindowReader.duration(of: url)
                try require(abs(duration - 100) < 0.01, "Durata letta dai frame errata: \(duration) s.")
                let windows = SpeechWindow.plan(duration: duration, maximum: 45)
                var frames: Int64 = 0
                for window in windows { frames += try AudioWindowReader.read(url: url, window: window) { _ in } }
                try require(windows.count == 3 && frames == 1_600_000, "I blocchi non coprono tutta la registrazione (\(frames) frame).")
                let words = (0..<30).map { TranscriptSegment(start: Double($0) * 0.4, duration: 0.3, text: "parola") }
                try require(TranscriptText.phrases(words).count < 10, "Le parole non vengono raggruppate in frasi.")
            }
            await check("Fogli continui: distacco ridotto e ordine delle coordinate") {
                let pages = [PageSnapshot(), PageSnapshot(), PageSnapshot()]
                let layout = ContinuousPageLayout(pages: pages)
                guard let first = layout.frame(pages[0].id), let second = layout.frame(pages[1].id) else { throw LibraryFailure.missingItem }
                try require(second.y - first.maxY == 12 && layout.mostVisible(top: second.y + 50, height: 500) == second.id,
                    "Distacco o ordine del flusso verticale errati.")
            }
        } catch { results.append(DiagnosticResult(title: "Preparazione test", passed: false, detail: error.localizedDescription)) }
    }

    private func verifyCanvasGeometry() throws {
        let canvas = PKCanvasView(), host = CanvasHost(canvas: canvas)
        let points = [CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        let erased = InkScratchEraser.erase(ink, in: CGRect(x: 100, y: 65, width: 60, height: 30))
        let reopened = try PKDrawing(data: erased.drawing.dataRepresentation())
        guard let mask = reopened.strokes.first?.mask else { throw DiagnosticFailure.assertion("Maschera della cancellazione mancante.") }
        try require(erased.erased && mask.contains(CGPoint(x: 40, y: 80)) && !mask.contains(CGPoint(x: 130, y: 80)), "La cancellazione non conserva l’inchiostro fuori dalla zona.")
        canvas.drawing = reopened
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
        host.canvas.zoomScale = host.canvas.minimumZoomScale * 2; host.fitPage(animated: false)
        try require(abs(host.canvas.zoomScale - host.canvas.minimumZoomScale) < 0.001 && host.bounds.insetBy(dx: -1, dy: -1).contains(host.surface.frame), "Il comando Pagina intera non adatta la geometria.")
        host.togglePageZoom(animated: false)
        try require(abs(host.surface.frame.minX) < 0.5 && abs(host.surface.frame.maxX - host.bounds.width) < 0.5,
            "Il doppio tocco non porta il foglio ai bordi laterali.")
        host.togglePageZoom(animated: false)
        try require(host.surface.frame.minX > 0 && abs(host.canvas.zoomScale - host.canvas.minimumZoomScale) < 0.001,
            "Il secondo doppio tocco non ripristina il foglio intero.")
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        try require(host.canvas.panGestureRecognizer.isEnabled && !host.canvas.panGestureRecognizer.allowedTouchTypes.contains(pencil),
            "Lo scorrimento del canvas non esclude Apple Pencil.")
    }

    private func writeSilence(_ url: URL, seconds: Int, rate: Double) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              let samples = buffer.floatChannelData else { throw DiagnosticFailure.assertion("Buffer audio di prova non disponibile.") }
        buffer.frameLength = frames; samples[0].initialize(repeating: 0, count: Int(frames))
        for _ in 0..<seconds { try file.write(from: buffer) }
    }

    private func verifyReadableTranscript() throws {
        var session = AudioSession(title: "Controllo lettura"); session.transcriptionComplete = true
        let segment = TranscriptSegment(start: 1, duration: 1, text: "Testo recuperato")
        session.transcriptionChunks = [TranscriptionChunk(file: "audio/control.caf", window: SpeechWindow(start: 0, duration: 45), language: "it-IT", segments: [segment])]
        try require(session.hasCompletedTranscript && session.readableTranscript.map(\.text) == ["Testo recuperato"], "I blocchi salvati non sono leggibili.")
        session.transcriptionChunks = []
        try require(!session.hasTranscriptText && !session.hasCompletedTranscript, "Un risultato vuoto viene presentato come testo salvato.")
    }
}
