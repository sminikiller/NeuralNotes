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
    var lensArea: CGRect?
    var lensRequest = 0
    var searchRequest = 0
    var focusRequest = 0
    var objectEditorRequest = 0
    var ink = Color.black
    var thickness: Double = 3
    var selectionWidth: Double = 3
    var fingerDrawing = false
    var workspaces = NotebookWorkspaces.starter()
    var shapeKind = ShapeKind.line
    var rulerActive = false
    @ObservationIgnored var workspaceSettingsDirty = false
    @ObservationIgnored var workspaceSaveTask: Task<Void, Never>?
    @ObservationIgnored weak var drawingAssistant: CanvasDrawingAssistant?
    @ObservationIgnored var pendingHeldShape: (page: UUID, kind: ShapeKind, samples: [StrokeSample])?
    var pageNavigation = PageNavigationMode.single {
        didSet {
            UserDefaults.standard.set(pageNavigation.rawValue, forKey: "editor.navigation.\(workspace.documentID)")
            canvasZoomed = false; fitPageRequest += 1
        }
    }
    var drawingShape = false
    var hasActiveStroke: Bool { usingInkTool || drawingShape }
    var interactionBusy: Bool { usingInkTool || editingTextID != nil || drawingShape }
    var fitPageRequest = 0
    var canvasZoomed = false
    var showZoomNavigator = false
    var laserActive = false
    var searchFocus: SearchFocusRequest?
    var editingTextID: UUID?
    @ObservationIgnored var textEditBefore: EditorContentState?
    var selectedIDs: Set<UUID> = []
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
    var backupWarning: String?
    func scheduleMaintenance() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.maintenanceTask = nil }
            _ = try? await self.workspace.indexedChunks()
            if UserDefaults.standard.object(forKey: "backup.automatic") as? Bool != false, let metadata = self.backupMetadata {
                do {
                    let created = try await self.workspace.createAutomaticBackup(metadata: metadata)
                    let latest: URL?
                    if let created { latest = created } else { latest = try await self.workspace.automaticBackups().first?.url }
                    if let latest { _ = try await ExternalBackupWriter.shared.copy(latest, documentID: self.workspace.documentID) }
                    self.backupWarning = nil
                }
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
        do {
            let catalog = try await workspace.catalog()
            sections = catalog.sections ?? []
            workspaces = catalog.editorWorkspaces ?? .starter(
                scratchErase: UserDefaults.standard.object(forKey: "editor.scratchErase") as? Bool ?? true,
                pullNext: UserDefaults.standard.object(forKey: "editor.pullNextPage") as? Bool ?? true)
            restoreToolPalette()
            pages = try await workspace.pages()
            if pages.isEmpty { pages = [try await workspace.addDefaultPage()] }
            let savedID = UserDefaults.standard.string(forKey: "editor.page.\(workspace.documentID)").flatMap(UUID.init(uuidString:))
            let lastEdited = try await workspace.lastEditedPage()
            if let first = lastEdited ?? pages.first(where: { $0.id == savedID }) ?? pages.first { try await load(first) }
            let recorder = AudioController(workspace: workspace)
            await recorder.load(); audio = recorder
        } catch { self.error = error.localizedDescription; status = "Apertura non riuscita" }
    }

    func configureTool() {
        if tool != .text { endTextEdit() }
        if tool != .objects { selectionIncludesInk = false; selectedStrokeIndices = nil }
        PaperInk.configure(canvas)
        switch tool {
        case .pen: canvas.tool = PKInkingTool(writingOptions.pen.native, color: PaperInk.color(ink), width: thickness)
        case .marker: canvas.tool = PKInkingTool(.marker, color: PaperInk.color(ink), width: max(12, thickness * 5))
        case .eraser: canvas.tool = PKEraserTool(writingOptions.eraser == .partial ? .bitmap : .vector, width: writingOptions.eraserWidth)
        case .lasso: canvas.tool = PKLassoTool()
        case .objects, .audioLink, .text, .shape, .lens: break
        }
        canvas.drawingGestureRecognizer.isEnabled = tool != .objects && tool != .audioLink && tool != .text && tool != .shape
        if tool == .lens { canvas.drawingGestureRecognizer.isEnabled = false }
        if laserActive { canvas.drawingGestureRecognizer.isEnabled = false }
        if tool == .eraser && writingOptions.markerOnly { canvas.drawingGestureRecognizer.isEnabled = false }
        canvas.isRulerActive = rulerActive && (tool == .pen || tool == .marker)
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        PaperInk.configureNavigation(canvas, fingerDrawing: fingerDrawing)
        if tool == .shape { canvas.panGestureRecognizer.minimumNumberOfTouches = 2 }
    }

    func drawingChanged() {
        guard !loading else { return }
        if tool == .eraser && drawingShape { return }
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
        guard await flush() else { return false }
        guard !hasActiveStroke else { return false }
        await audio?.close()
        EditorLeases.shared.release(document: workspace.documentID, owner: leaseOwner); hasLease = false
        return true
    }

    private func signatures() -> [String] {
        EditorInkSignatures.make(canvas.drawing)
    }

    func strokeBegan() {
        searchFocus = nil
        finishInkGesture()
        rememberPalette()
        usingInkTool = true
        editBeforeGesture = captureEdit(ink: true)
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

    /// PencilKit can deliver the final drawing after didEndUsingTool.
    /// Retain the before-state until there is an actual committed change.
    func finishInkGesture() {
        guard !usingInkTool, !finishingInkGesture, let before = editBeforeGesture,
              before.drawing != canvas.drawing.dataRepresentation() else { return }
        gestureCommitTask?.cancel(); gestureCommitTask = nil
        finishingInkGesture = true; defer { finishingInkGesture = false }
        let shaped = applyHeldShapeIfNeeded()
        let scratched = shaped ? false : eraseScratchIfNeeded()
        drawingAssistant?.finishPreview()
        if let (session, time) = strokeTime, var page {
            let existing = Set(page.anchors.map(\.signature))
            for signature in signatures() {
                if !existing.contains(signature), !signaturesBeforeStroke.contains(signature) {
                    page.anchors.append(StrokeAnchor(signature: signature, audioSessionID: session, seconds: time))
                }
            }
            self.page = page
        }
        strokeTime = nil
        editBeforeGesture = nil
        recordEdit(before, label: shaped ? "Forma precisa" : scratched ? "Scarabocchio: cancella" : "Inchiostro")
        drawingChanged()
        if tool == .eraser && writingOptions.returnToPen { chooseTool(.pen) }
    }

    @discardableResult
    func flush() async -> Bool {
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
                scheduleMaintenance()
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
        // Fetch latest header after a pending flush, never a stale thumbnail snapshot.
        pages = try await workspace.pages()
        guard let current = pages.first(where: { $0.id == target.id }) else { throw LibraryFailure.missingItem }
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

    private func installPage(_ current: PageSnapshot, drawing: PKDrawing, recovered: Bool) {
        lensArea = nil
        pendingHeldShape = nil; drawingAssistant?.cancel()
        gestureCommitTask?.cancel(); gestureCommitTask = nil; editBeforeGesture = nil; usingInkTool = false; strokeTime = nil
        endTextEdit()
        let delegate = canvas.delegate
        canvas.delegate = nil
        defer { canvas.delegate = delegate }
        canvas.drawing = drawing
        canvas.undoManager?.removeAllActions()
        page = current; selectedObjectID = nil; dirty = recovered; recoveredFromPrevious = recovered
        status = recovered ? "Revisione precedente recuperata — salva" : "Salvato sul dispositivo"
        configureTool()
        (pagePresenter as? CanvasHost)?.synchronizePage()
        UserDefaults.standard.set(current.id.uuidString, forKey: "editor.page.\(workspace.documentID)")
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

    func deletePage() async {
        guard hasLease, !navigating, !hasActiveStroke else { return }
        navigating = true; defer { navigating = false }
        guard let page, await flush(), !hasActiveStroke else { return }
        let before = pages.map(\.id)
        do {
            try await workspace.deletePage(page.id)
            pages = try await workspace.pages()
            if pages.isEmpty { pages = [try await workspace.addDefaultPage()] }
            if let first = pages.first { try await load(first) }
            recordOrder(before, selectedBefore: page.id, label: "Elimina pagina")
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
        if selectedIDs.count > 1 || selectionIncludesInk { if copySelection() { Task { await pasteSelection() } }; return }
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

    func playAudio(at point: CGPoint, tolerance: CGFloat) async {
        guard let page, let audio else { return }
        let keys = signatures()
        // Use the interpolated curve, rather than the whole bounding
        // rectangle of a long stroke, to avoid jumping to unrelated handwriting.
        var nearest: (StrokeAnchor, CGFloat)?
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
