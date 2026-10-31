import SwiftUI
import PencilKit
import Observation
import NeuralNotesCore

enum InkTool: String, CaseIterable {
    case pen = "Penna", marker = "Evidenziatore", eraser = "Gomma", lasso = "Lazo"
    case objects = "Oggetti", audioLink = "Ascolta tratto", text = "Testo con Pencil", shape = "Forme"
    case lens = "Lente AI"
    var icon: String {
        switch self {
        case .pen: return "pencil.tip"; case .marker: return "highlighter"; case .eraser: return "eraser"
        case .lasso: return "lasso"; case .objects: return "cursorarrow.and.square.on.square.dashed"; case .audioLink: return "waveform"
        case .text: return "character.cursor.ibeam"
        case .shape: return "circle.square"
        case .lens: return "sparkle.magnifyingglass"
        }
    }
}

@MainActor
protocol EditorPagePresenter: AnyObject {
    func presentPage(_ target: PageSnapshot, load: @MainActor () async throws -> Void) async throws
}

@MainActor @Observable
final class EditorViewModel {
    let workspace: DocumentWorkspace
    @ObservationIgnored let canvas = PKCanvasView()
    @ObservationIgnored weak var pagePresenter: (any EditorPagePresenter)?
    var pages: [PageSnapshot] = []
    var sections: [NotebookSection] = []
    var page: PageSnapshot?
    var tool = InkTool.pen
    @ObservationIgnored var toolBeforeLens = InkTool.pen
    var lensArea: CGRect?
    var lensTextSelection: String?
    var lensPrefersPopup = false
    var lensRequest = 0
    /// The Lens conversation about the last selection, the tab of the Lens side panel,
    /// a request to show that panel, the note outlined after a jump and the note to edit.
    var lensSession: LensSession?
    var lensTab = LensTab.selection
    var lensPanelRequest = 0
    var lensNoteFocus: LensNoteFocus?
    var lensNoteEditor: LensNoteEditTarget?
    /// Words picked with the Lens and waiting for a command, their highlight, and a
    /// search to start from them.
    var lensPick: LensPick?
    var lensHighlight: LensHighlight?
    var pendingSearchQuery: String?
    /// Where the last Lens gesture was, in editor view coordinates, and the notebook title as subject.
    @ObservationIgnored var lensAnchor: CGRect?
    var lensSubject = ""
    var searchRequest = 0
    var focusRequest = 0
    var selectionImageShareRequest = 0
    var objectEditorRequest = 0
    var imageStraightenRequest = 0
    var ink = Color.black
    var thickness: Double = 3
    var selectionWidth: Double = 3
    var fingerDrawing = false
    var workspaces = NotebookWorkspaces.starter()
    var shapeKind = ShapeKind.line
    var rulerActive = false
    var rulerGuide = RulerGuide()
    var protractorActive = false
    var protractorGuide = ProtractorGuide()
    var protractorMeasure = false
    var protractorRays: [Double] = []
    var guideReadout: String?
    @ObservationIgnored var protractorDrawing = false
    @ObservationIgnored var workspaceSettingsDirty = false
    @ObservationIgnored var workspaceSaveTask: Task<Void, Never>?
    @ObservationIgnored weak var drawingAssistant: CanvasDrawingAssistant?
    @ObservationIgnored var inkDisplayGeneration = UUID()
    @ObservationIgnored var inkGestureGeneration = UUID()
    @ObservationIgnored var inkGestureBaseline: PKDrawing?
    @ObservationIgnored var eraserCompositionToken: UUID?
    @ObservationIgnored var pendingHeldShape: (page: UUID, kind: ShapeKind, samples: [StrokeSample])?
    @ObservationIgnored var pendingShapeRecognition: ShapeRecognitionResult?
    @ObservationIgnored var pendingAutomaticRecognition = false
    var recognitionNotice: String?
    @ObservationIgnored var recognitionNoticeTask: Task<Void, Never>?
    var shapeStyleRequest = 0
    var connectorStyleRequest = 0
    var diagramLabelEditor: DiagramLabelEditTarget?
    var pageNavigation = PageNavigationMode.single {
        didSet {
            UserDefaults.standard.set(pageNavigation.rawValue, forKey: "editor.navigation.\(workspace.documentID)")
            canvasZoomed = false; fitPageRequest += 1
        }
    }
    var drawingShape = false
    @ObservationIgnored var movingObjects = false
    var hasActiveStroke: Bool { usingInkTool || drawingShape || movingObjects }
    var interactionBusy: Bool { usingInkTool || editingTextID != nil || drawingShape || movingObjects }
    var fitPageRequest = 0
    var canvasZoomed = false
    var canvasViewportMoving = false
    var showZoomNavigator = false
    var laserActive = false
    var searchFocus: SearchFocusRequest?
    var editingTextID: UUID?
    @ObservationIgnored var textEditBefore: EditorContentState?
    var selectedIDs: Set<UUID> = []
    var selectionPageDragMode = false { didSet { configureTool() } }
    var selectionDragCopy = false
    var selectionDropPending = false
    @ObservationIgnored let selectionDragOwner = UUID()
    @ObservationIgnored var activeSelectionPageDrag: SelectionPageDragRecord?
    var selectionIncludesInk = false
    var selectedStrokeIndices: Set<Int>?
    var selectedInkBounds: CGRect {
        guard let selectedStrokeIndices else { return canvas.drawing.bounds }
        let rect = selectedStrokeIndices.filter { canvas.drawing.strokes.indices.contains($0) }
            .reduce(CGRect.null) { $0.union(canvas.drawing.strokes[$1].renderBounds) }
        return rect.isNull ? .zero : rect
    }
    var selectedObjectID: UUID? {
        get { selectedIDs.first }
        set { selectedIDs = newValue.map { [$0] } ?? []; selectionIncludesInk = false; selectedStrokeIndices = nil }
    }
    var multiSelection = false
    var selectRectangle = false
    var selectFreehand = false
    var history = EditHistory<EditorEdit>()
    var applyingHistory = false
    @ObservationIgnored var editBeforeGesture: EditorContentState?
    @ObservationIgnored private var usingInkTool = false
    @ObservationIgnored private var finishingInkGesture = false
    @ObservationIgnored private var gestureCommitTask: Task<Void, Never>?
    @ObservationIgnored private let leaseOwner = UUID()
    private(set) var hasLease = false
    var error: String?
    var dirty = false
    @ObservationIgnored var backupMetadata: Notebook?
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var maintenanceGeneration = UUID()
    @ObservationIgnored var maintenanceDelay: Duration = .seconds(8)
    var openingTimings: [String: Double] = [:]
    var backupWarning: String?
    func cancelMaintenance() {
        maintenanceGeneration = UUID(); maintenanceTask?.cancel(); maintenanceTask = nil
    }
    func scheduleMaintenance() {
        cancelMaintenance()
        let generation = maintenanceGeneration, delay = maintenanceDelay
        maintenanceTask = Task(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.maintenanceGeneration == generation else { return }
            defer { if self.maintenanceGeneration == generation { self.maintenanceTask = nil } }
            guard self.hasLease, !self.interactionBusy, !self.dirty, !self.saving, !self.loading, !self.navigating,
                  self.audio?.recording != true else { return }
            _ = try? await self.workspace.indexedChunks()
            guard !Task.isCancelled else { return }
            if UserDefaults.standard.object(forKey: "backup.automatic") as? Bool != false, let metadata = self.backupMetadata {
                do {
                    let created = try await self.workspace.createAutomaticBackup(metadata: metadata)
                    let latest: URL?
                    if let created { latest = created } else { latest = try await self.workspace.automaticBackups().first?.url }
                    if let latest { _ = try await ExternalBackupWriter.shared.copy(latest, documentID: self.workspace.documentID) }
                    self.backupWarning = nil
                }
                catch is CancellationError { return }
                catch { self.backupWarning = "Backup automatico da riprovare: \(error.localizedDescription)" }
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard self.hasLease, !self.hasActiveStroke, !self.dirty, self.audio?.recording != true,
                  UserDefaults.standard.object(forKey: "search.automaticOCR") as? Bool != false,
                  let page = self.page, page.revision > 0,
                  await self.workspace.needsAutomaticOCR(pageID: page.id, revision: page.revision) else { return }
            do {
                let image = DocumentServices.image(page: page, drawing: self.canvas.drawing, workspace: self.workspace, maxDimension: 1600)
                guard let data = image.pngData() else { return }
                let text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
                _ = try await self.workspace.storeAutomaticOCR(pageID: page.id, revision: page.revision, text: text)
                _ = try await self.workspace.indexedChunks()
            } catch { /* OCR is derived and optional; notebook contents remain authoritative. */ }
        }
    }
    var saving = false
    var loading = false
    var navigating = false
    var status = "Apertura…"
    var audio: AudioController?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var savingTask: Task<Bool, Never>?
    @ObservationIgnored private var strokeTime: (UUID, Double)?
    @ObservationIgnored private var signaturesBeforeStroke = Set<String>()
    @ObservationIgnored private var recoveredFromPrevious = false
    @ObservationIgnored private let pageWriter: @MainActor (PageSnapshot, Data, Bool) async throws -> PageSnapshot

    init(workspace: DocumentWorkspace, pageWriter: (@MainActor (PageSnapshot, Data, Bool) async throws -> PageSnapshot)? = nil) {
        self.workspace = workspace
        self.pageWriter = pageWriter ?? { page, data, recovered in
            try await workspace.save(page, drawing: data, recoveredFromPrevious: recovered)
        }
        pageNavigation = UserDefaults.standard.string(forKey: "editor.navigation.\(workspace.documentID)")
            .flatMap(PageNavigationMode.init(rawValue:)) ?? .single
    }

    func open() async {
        guard pages.isEmpty, page == nil else { return }
        guard EditorLeases.shared.acquire(document: workspace.documentID, owner: leaseOwner, editor: self) else {
            error = "Questo quaderno è già aperto in un’altra finestra. Chiudilo lì prima di modificarlo qui."
            status = "Aperto in un’altra finestra"; return
        }
        hasLease = true
        let started = ProcessInfo.processInfo.systemUptime
        var stage = started
        openingTimings = [:]
        do {
            let catalog = try await workspace.catalog()
            openingTimings["Catalogo"] = (ProcessInfo.processInfo.systemUptime - stage) * 1000
            stage = ProcessInfo.processInfo.systemUptime
            sections = catalog.sections ?? []
            workspaces = catalog.editorWorkspaces ?? .starter(
                scratchErase: UserDefaults.standard.object(forKey: "editor.scratchErase") as? Bool ?? true,
                pullNext: UserDefaults.standard.object(forKey: "editor.pullNextPage") as? Bool ?? true)
            restoreToolPalette()
            pages = try await workspace.pages()
            if pages.isEmpty { pages = [try await workspace.addDefaultPage()] }
            let savedID = UserDefaults.standard.string(forKey: "editor.page.\(workspace.documentID)").flatMap(UUID.init(uuidString:))
            // Metadata was already read above. Do not scan the whole document
            // again to choose a page or when installing its drawing.
            let lastEdited = pages.filter { $0.lastEditedAt != nil }.max { ($0.lastEditedAt ?? 0) < ($1.lastEditedAt ?? 0) }
            openingTimings["Metadati pagine"] = (ProcessInfo.processInfo.systemUptime - stage) * 1000
            stage = ProcessInfo.processInfo.systemUptime
            if let first = lastEdited ?? pages.first(where: { $0.id == savedID }) ?? pages.first { try await load(first) }
            openingTimings["Pagina e inchiostro"] = (ProcessInfo.processInfo.systemUptime - stage) * 1000
            openingTimings["Foglio pronto"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let recorder = AudioController(workspace: workspace)
            stage = ProcessInfo.processInfo.systemUptime
            await recorder.load(catalog: catalog)
            guard hasLease, !Task.isCancelled else { await recorder.close(); return }
            audio = recorder
            openingTimings["Recupero audio"] = (ProcessInfo.processInfo.systemUptime - stage) * 1000
            scheduleMaintenance()
        } catch { self.error = error.localizedDescription; status = "Apertura non riuscita" }
    }

    func configureTool() {
        if tool != .text { endTextEdit() }
        if tool != .objects { selectionIncludesInk = false; selectedStrokeIndices = nil }
        PaperInk.configure(canvas)
        switch tool {
        case .pen: canvas.tool = PKInkingTool(writingOptions.pen.native, color: PaperInk.color(ink), width: thickness)
        case .marker: canvas.tool = PKInkingTool(.marker, color: PaperInk.color(ink), width: markerWidth)
        case .eraser: canvas.tool = PKEraserTool(writingOptions.eraser == .partial ? .bitmap : .vector, width: writingOptions.eraserWidth)
        case .lasso: canvas.tool = PKLassoTool()
        case .objects, .audioLink, .text, .shape, .lens: break
        }
        canvas.drawingGestureRecognizer.isEnabled = tool != .objects && tool != .audioLink && tool != .text && tool != .shape
        if tool == .lens { canvas.drawingGestureRecognizer.isEnabled = false }
        if laserActive { canvas.drawingGestureRecognizer.isEnabled = false }
        if tool == .eraser { canvas.drawingGestureRecognizer.isEnabled = false }
        if selectionPageDragMode { canvas.drawingGestureRecognizer.isEnabled = false }
        canvas.isRulerActive = false
        if (rulerActive || protractorDrawing) && (tool == .pen || tool == .marker) { canvas.drawingGestureRecognizer.isEnabled = false }
        if markerCustomInput { canvas.drawingGestureRecognizer.isEnabled = false }
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        PaperInk.configureNavigation(canvas, fingerDrawing: fingerDrawing)
        if tool == .shape { canvas.panGestureRecognizer.minimumNumberOfTouches = 2 }
        if tool == .marker, writingOptions.markerSnapWords != false, let page { PageWordIndex.shared.preparePDFMarker(page, model: self) }
    }

    func drawingChanged(preservingRecognizedWords: Bool = false) {
        guard !loading else { return }
        guard !movingObjects else { return }
        inkDisplayGeneration = UUID()
        (canvas.superview as? CanvasHost)?.markerReadability.update(canvas.superview as? CanvasHost)
        if tool == .eraser && drawingShape { return }
        if let page {
            let markerGesture = !applyingHistory && ((tool == .marker && (usingInkTool || finishingInkGesture)) ||
                (tool == .eraser && writingOptions.effectiveEraserTarget == .marker && (usingInkTool || drawingShape)))
            let preserve = preservingRecognizedWords || markerGesture
            PageWordIndex.shared.invalidate(page, preservingRecognizedWords: preserve)
        }
        if tool == .marker, !hasActiveStroke { configureTool() }
        if editBeforeGesture != nil && !usingInkTool && !finishingInkGesture { scheduleInkCommit() }
        dirty = true; status = "Modifiche da salvare"
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self else { return }
            _ = await self.flush()
        }
    }

    func close() async -> Bool {
        guard !hasActiveStroke else { return false }
        cancelMaintenance()
        guard await flush() else { return false }
        guard !hasActiveStroke else { return false }
        cancelMaintenance()
        await audio?.close()
        EditorLeases.shared.release(document: workspace.documentID, owner: leaseOwner); hasLease = false
        return true
    }

    private func signatures() -> [String] {
        EditorInkSignatures.make(canvas.drawing)
    }

    func strokeBegan() {
        guard hasLease, !loading, !navigating else { return }
        cancelMaintenance()
        searchFocus = nil
        recognitionNoticeTask?.cancel(); recognitionNotice = nil
        finishInkGesture()
        rememberPalette()
        usingInkTool = true
        editBeforeGesture = captureEdit(ink: true)
        inkGestureBaseline = canvas.drawing; inkGestureGeneration = UUID()
        strokeTime = audio?.recordingAnchor
        signaturesBeforeStroke = Set(signatures())
    }

    func strokeEnded() {
        usingInkTool = false
        scheduleInkCommit()
    }

    private func scheduleInkCommit() {
        gestureCommitTask?.cancel()
        gestureCommitTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            self?.finishInkGesture()
        }
    }

    /// didEndUsingTool can precede the final drawing notification. An undo
    /// command must settle that stroke before choosing its history entry.
    func settleInkBeforeHistory() async -> Bool {
        for _ in 0..<20 {
            finishInkGesture()
            guard editBeforeGesture != nil else { return true }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        finishInkGesture()
        // Never undo the preceding action when PencilKit has not delivered the
        // current stroke yet. Keep it pending rather than reviving late ink.
        return editBeforeGesture == nil && !Task.isCancelled
    }

    /// PencilKit can deliver the final drawing after didEndUsingTool.
    /// Retain the before-state until there is an actual committed change.
    func finishInkGesture() {
        guard !usingInkTool, !finishingInkGesture, let before = editBeforeGesture,
              before.drawing != canvas.drawing.dataRepresentation() else { return }
        gestureCommitTask?.cancel(); gestureCommitTask = nil
        finishingInkGesture = true; defer { finishingInkGesture = false }
        if let (session, time) = strokeTime, var page {
            let existing = Set(page.anchors.map(\.signature))
            for signature in signatures() {
                if !existing.contains(signature), !signaturesBeforeStroke.contains(signature) {
                    page.anchors.append(StrokeAnchor(signature: signature, audioSessionID: session, seconds: time))
                }
            }
            self.page = page
        }
        let raw = captureEdit(ink: true)
        let automatic = pendingAutomaticRecognition
        let recognizedTitle = pendingHeldShape?.kind.title
        let shaped = applyHeldShapeIfNeeded()
        let scratched = shaped || rulerActive || protractorDrawing ? false : eraseScratchIfNeeded()
        drawingAssistant?.finishPreview()
        strokeTime = nil
        editBeforeGesture = nil
        inkGestureBaseline = nil
        if shaped, let raw, before != raw {
            let metadata = (try? JSONEncoder().encode(before.page).count) ?? 0
            history.record(.content(before, raw), label: "Inchiostro", cost: (before.drawing?.count ?? 0) + (raw.drawing?.count ?? 0) + metadata * 2)
            recordEdit(raw, label: "Forma precisa")
        } else { recordEdit(before, label: scratched ? "Scarabocchio: cancella" : "Inchiostro") }
        if automatic, shaped, let recognizedTitle { showRecognitionNotice(recognizedTitle) }
        drawingChanged()
        if tool == .eraser && writingOptions.returnToPen { chooseTool(.pen) }
        if tool == .marker { configureTool() }
    }

    @discardableResult
    func flush() async -> Bool {
        cancelMaintenance()
        var wrotePage = false
        // Ink is committed before optional toolbar settings. A damaged catalog
        // must never stop an otherwise valid page from reaching disk.
        while true {
            finishInkGesture()
            commitTextEdit()
            debounce?.cancel(); debounce = nil
            while saving, let task = savingTask {
                if !(await task.value) { return false }
                await Task.yield()
            }
            guard dirty, var snapshot = page else {
                guard await saveWorkspaceSettings() else { return false }
                if dirty { continue }
                if wrotePage { scheduleMaintenance() }
                return true
            }
            guard hasLease else { return false }
            snapshot.revision += 1
            let data = canvas.drawing.dataRepresentation()
            let recovering = recoveredFromPrevious
            dirty = false; saving = true; status = "Salvataggio…"
            let task = Task { [weak self, pageWriter] () -> Bool in
                do {
                    let saved = try await pageWriter(snapshot, data, recovering)
                    guard let self else { return true }
                    if self.page?.id == saved.id {
                        self.recoveredFromPrevious = false
                        self.page?.revision = saved.revision
                        self.page?.drawingFile = saved.drawingFile
                        self.page?.previousDrawingFile = saved.previousDrawingFile
                        self.page?.lastEditedAt = saved.lastEditedAt
                        if let index = self.pages.firstIndex(where: { $0.id == saved.id }), let current = self.page {
                            self.pages[index] = current
                        }
                    }
                    self.status = self.dirty ? "Modifiche da salvare" : "Salvato sul dispositivo"
                    return true
                } catch {
                    self?.dirty = true; self?.error = error.localizedDescription
                    self?.status = "Salvataggio non riuscito — riprova"
                    return false
                }
            }
            savingTask = task
            let result = await task.value
            savingTask = nil; saving = false
            guard result else { return false }
            wrotePage = true
            // An edit can arrive while the actor writes this snapshot. Drain those
            // changes before a caller is allowed to navigate or close the editor.
        }
    }

    func select(_ target: PageSnapshot) async {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard await flush() else { return }
        guard !hasActiveStroke else { return }
        guard target.id != page?.id else { return }
        do {
            if pageNavigation == .horizontal, let pagePresenter {
                try await pagePresenter.presentPage(target) { try await self.load(target) }
            } else { try await load(target) }
        } catch { self.error = error.localizedDescription }
    }

    func load(_ target: PageSnapshot) async throws {
        loading = true
        defer { loading = false }
        // Only the destination needs a fresh header. The workspace verifies
        // manifest membership; unrelated pages/media are not part of this read.
        let current = try await workspace.pageSnapshot(target.id)
        if let index = pages.firstIndex(where: { $0.id == target.id }) { pages[index] = current }
        else {
            // Add/duplicate/mind-map can publish a new page before the model's
            // list is updated. Trust verified manifest membership, not the old UI.
            let order = try await workspace.manifest().pageIDs
            var known = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
            known[current.id] = current
            if order.allSatisfy({ known[$0] != nil }) { pages = order.compactMap { known[$0] } }
            else { pages = try await workspace.pages() }
        }
        let drawing: PKDrawing
        var recovered = false
        do {
            let data = try await workspace.drawing(current)
            drawing = try data.map { try PKDrawing(data: $0) } ?? PKDrawing()
        }
        catch {
            guard let backup = current.previousDrawingFile else { throw error }
            let url = try await workspace.url(backup)
            drawing = try PKDrawing(data: Data(contentsOf: url))
            recovered = true
            self.error = "Recuperata la revisione precedente. Salva per conservarla."
        }
        installPage(current, drawing: drawing, recovered: recovered)
    }

    /// Only a clean editor may switch synchronously at Pencil touch-down.
    /// Cached headers must still match the current document snapshot exactly.
    func activatePreparedPage(_ target: PageSnapshot, drawing: PKDrawing) -> Bool {
        guard hasLease, !loading, !navigating, !interactionBusy, !dirty, !saving,
              pages.first(where: { $0.id == target.id }) == target else { return false }
        loading = true; defer { loading = false }
        installPage(target, drawing: drawing, recovered: false)
        return true
    }

    /// Drop pending editor work and install a fresh drawing container. The caller
    /// has already finished the native stroke and locked input for history/load.
    func replaceInkSession(with drawing: PKDrawing) {
        let delegate = canvas.delegate
        canvas.delegate = nil
        drawingAssistant?.cancel()
        pendingHeldShape = nil
        pendingShapeRecognition = nil; pendingAutomaticRecognition = false
        recognitionNoticeTask?.cancel(); recognitionNotice = nil
        gestureCommitTask?.cancel(); gestureCommitTask = nil
        editBeforeGesture = nil; usingInkTool = false; strokeTime = nil
        inkGestureBaseline = nil
        signaturesBeforeStroke = []
        // Keep the original stroke objects (ink, masks and transforms), but use
        // a fresh drawing container rather than the old native editing timeline.
        installNativeInk(drawing)
        canvas.delegate = delegate
    }

    /// End the native editing timeline as well as replacing its value. Otherwise
    /// PencilKit may append its previous raw stroke on the next tool gesture.
    func installNativeInk(_ drawing: PKDrawing) {
        let delegate = canvas.delegate, enabled = canvas.drawingGestureRecognizer.isEnabled
        canvas.delegate = nil
        canvas.drawingGestureRecognizer.isEnabled = false
        canvas.drawing = PKDrawing(strokes: drawing.strokes)
        canvas.undoManager?.removeAllActions()
        canvas.drawingGestureRecognizer.isEnabled = enabled
        canvas.delegate = delegate; inkDisplayGeneration = UUID()
    }

    private func installPage(_ current: PageSnapshot, drawing: PKDrawing, recovered: Bool) {
        lensArea = nil; lensTextSelection = nil; lensPick = nil; lensHighlight = nil
        endTextEdit()
        replaceInkSession(with: drawing)
        page = current; selectedObjectID = nil; diagramLabelEditor = nil; dirty = recovered; recoveredFromPrevious = recovered
        status = recovered ? "Revisione precedente recuperata — salva" : "Salvato sul dispositivo"
        configureTool()
        (pagePresenter as? CanvasHost)?.synchronizePage()
        UserDefaults.standard.set(current.id.uuidString, forKey: "editor.page.\(workspace.documentID)")
        if tool == .lens { prepareLensWords() }
    }

    func addPage() async {
        guard hasLease, !navigating, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard await flush(), !hasActiveStroke else { return }
        let before = pages.map(\.id), selected = page?.id
        do {
            let catalog = try await workspace.catalog()
            var next = catalog.defaultPageTemplate?.makePage() ?? PageSnapshot()
            if catalog.defaultPageTemplate == nil, let page {
                next.width = page.width; next.height = page.height; next.paper = page.paper; next.appearance = page.appearance
            }
            let new = try await workspace.addPage(next); try await load(new)
            recordOrder(before, selectedBefore: selected, label: "Aggiungi pagina")
        }
        catch { self.error = error.localizedDescription }
    }

    func duplicatePage() async {
        guard hasLease, !navigating, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard let page, await flush(), !hasActiveStroke else { return }
        let before = pages.map(\.id)
        do { let new = try await workspace.duplicatePage(page.id); try await load(new); recordOrder(before, selectedBefore: page.id, label: "Duplica pagina") }
        catch { self.error = error.localizedDescription }
    }
    func insertBlankPageAfterCurrent() async {
        guard hasLease, !navigating, !hasActiveStroke, let current = page, await flush() else { return }
        navigating = true; defer { navigating = false }
        do {
            let before = try await workspace.pages().map(\.id)
            var blank = PageSnapshot(); blank.width = current.width; blank.height = current.height; blank.paper = current.paper; blank.appearance = current.appearance
            let created = try await workspace.addPage(blank)
            var order = before; order.insert(created.id, at: min(order.count, (order.firstIndex(of: current.id) ?? order.count - 1) + 1))
            try await workspace.reorderPages(order); try await load(created)
            recordOrder(before, selectedBefore: current.id, label: "Inserisci pagina bianca")
        } catch { self.error = error.localizedDescription }
    }

    func deletePage(_ pageID: UUID? = nil) async {
        guard let target = pageID ?? page?.id else { return }
        await deletePages([target])
    }
    func deletePages(_ ids: Set<UUID>) async {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard let page, await flush(), !hasActiveStroke else { return }
        guard !ids.isEmpty, ids.isSubset(of: Set(pages.map(\.id))) else { return }
        let removedIndex = pages.firstIndex(where: { ids.contains($0.id) }) ?? 0
        let before = pages.map(\.id)
        do {
            try await workspace.deletePages(ids)
            pages = try await workspace.pages()
            if pages.isEmpty { pages = [try await workspace.addDefaultPage()] }
            let selected = ids.contains(page.id) ? pages[min(removedIndex, pages.count - 1)] : pages.first(where: { $0.id == page.id }) ?? pages[0]
            try await load(selected)
            recordOrder(before, selectedBefore: page.id, label: ids.count == 1 ? "Elimina pagina" : "Elimina pagine")
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func restorePages(_ ids: [UUID]) async {
        guard hasLease, !loading, !navigating, !interactionBusy, await flush() else { return }
        navigating = true; defer { navigating = false }
        let before = pages.map(\.id), selected = page?.id
        do {
            try await workspace.restoreRemovedPages(ids)
            pages = try await workspace.pages()
            recordOrder(before, selectedBefore: selected, label: "Ripristina pagine")
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func setPaper(_ paper: PaperStyle) { mutatePage("Sfondo") { $0.paper = paper } }
    func setPageDetails(_ target: PageSnapshot, title: String?, bookmarked: Bool) async {
        guard hasLease, !navigating, !loading, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard await flush(), !hasActiveStroke else { return }
        let before = target.id == page?.id ? captureEdit() : EditorContentState(page: target, drawing: nil)
        do {
            let saved = try await workspace.setPageDetails(target.id, title: title, bookmarked: bookmarked)
            if page?.id == saved.id { page = saved }
            pages = try await workspace.pages()
            let after = EditorContentState(page: saved, drawing: nil)
            if let before, before != after { history.record(.content(before, after), label: "Titolo e segnalibro") }
        } catch { self.error = error.localizedDescription }
    }
    func editText(_ texts: [TextElement]) { mutatePage("Modifica testo") { $0.texts = texts } }
    func editImages(_ images: [ImageElement]) { mutatePage("Modifica immagini") { $0.images = images } }
    func editElements(texts: [TextElement], images: [ImageElement], shapes: [ShapeElement]) {
        mutatePage("Modifica oggetti") { $0.texts = texts; $0.images = images; $0.shapes = shapes }
    }

    func deleteSelectedObject() {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        finishInkGesture(); endTextEdit()
        let before = captureEdit(ink: selectionIncludesInk)
        let ids = selectedIDs
        page?.texts.removeAll { ids.contains($0.id) }; page?.images.removeAll { ids.contains($0.id) }
        page?.shapes?.removeAll { ids.contains($0.id) }
        page?.connectors?.removeAll { ids.contains($0.id) }
        page?.tapes?.removeAll { ids.contains($0.id) }; page?.pruneObjectReferences()
        if selectionIncludesInk {
            if let selectedStrokeIndices { canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().filter { !selectedStrokeIndices.contains($0.offset) }.map(\.element)) }
            else { canvas.drawing = PKDrawing() }
        }
        recordEdit(before, label: "Elimina selezione")
        selectedObjectID = nil; drawingChanged()
    }

    func duplicateSelectedObject() {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        finishInkGesture(); endTextEdit()
        if selectedIDs.count > 1 || selectionIncludesInk || selectedConnector != nil { if copySelection() { Task { await pasteSelection() } }; return }
        let before = captureEdit()
        guard let id = selectedObjectID else { return }
        if var text = page?.texts.first(where: { $0.id == id }) {
            text.id = UUID(); text.x += 20; text.y += 20
            page?.texts.append(text); selectedObjectID = text.id
        } else if var image = page?.images.first(where: { $0.id == id }) {
            image.id = UUID(); image.x += 20; image.y += 20
            page?.images.append(image); selectedObjectID = image.id
        } else if var shape = page?.shapes?.first(where: { $0.id == id }) {
            shape.id = UUID(); shape.x += 20; shape.y += 20
            page?.shapes?.append(shape); selectedObjectID = shape.id
        } else if var tape = page?.tapes?.first(where: { $0.id == id }) {
            tape.id = UUID(); tape.x += 20; tape.y += 20
            page?.tapes?.append(tape); selectedObjectID = tape.id
        }
        if let copied = selectedObjectID, copied != id {
            if page?.aboveInkObjects?.contains(id) == true { page?.aboveInkObjects?.append(copied) }
            if let order = page?.objectOrder { page?.objectOrder = order + [copied] }
        }
        recordEdit(before, label: "Duplica oggetto")
        drawingChanged()
    }
    func cancelGuidedInk(_ drawing: PKDrawing) {
        usingInkTool = false; editBeforeGesture = nil; strokeTime = nil; drawingShape = false
        inkGestureBaseline = nil
        gestureCommitTask?.cancel(); gestureCommitTask = nil
        installNativeInk(drawing)
    }

    func playAudio(at point: CGPoint, tolerance: CGFloat) async {
        guard let page, let audio else { return }
        let keys = signatures()
        // Use the interpolated curve, rather than the whole bounding
        // rectangle of a long stroke, to avoid jumping to unrelated handwriting.
        var nearest: (StrokeAnchor, CGFloat)?
        for shape in page.shapes ?? [] {
            if let anchor = shape.audioAnchor,
               ShapeGeometry.hit(.init(x: point.x, y: point.y), shape: shape, zoom: canvas.zoomScale) {
                nearest = (anchor, 0); break
            }
        }
        if nearest == nil, page.connectors?.isEmpty == false {
            let objects = DiagramObjects.make(page)
            for edge in page.connectors ?? [] {
                if let anchor = edge.audioAnchor, ConnectorGeometry.hit(.init(x: point.x, y: point.y), connector: edge, objects: objects, zoom: canvas.zoomScale) {
                    nearest = (anchor, 0); break
                }
            }
        }
        for (index, stroke) in canvas.drawing.strokes.enumerated() {
            guard let anchor = page.anchors.first(where: { $0.signature == keys[index] }),
                  stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let points = stroke.path.interpolatedPoints(by: .distance(6)).map { $0.location.applying(stroke.transform) }
            var distance = CGFloat.greatestFiniteMagnitude
            for pair in zip(points, points.dropFirst()) {
                let dx = pair.1.x - pair.0.x, dy = pair.1.y - pair.0.y
                let length = dx * dx + dy * dy
                let t = length > 0 ? max(0, min(1, ((point.x - pair.0.x) * dx + (point.y - pair.0.y) * dy) / length)) : 0
                distance = min(distance, hypot(point.x - pair.0.x - t * dx, point.y - pair.0.y - t * dy))
            }
            if let first = points.first { distance = min(distance, hypot(point.x - first.x, point.y - first.y)) }
            if distance <= tolerance, nearest == nil || distance < nearest!.1 { nearest = (anchor, distance) }
        }
        guard let anchor = nearest?.0,
              let session = audio.sessions.first(where: { $0.id == anchor.audioSessionID })
                ?? (audio.active?.id == anchor.audioSessionID ? audio.active : nil) else {
            error = "Questo tratto non ha un collegamento audio. Scrivi durante una registrazione per crearne uno."; return
        }
        if audio.recording { await audio.pause(reason: "Ascolto di un tratto") }
        await audio.play(session, at: anchor.seconds)
    }
}
