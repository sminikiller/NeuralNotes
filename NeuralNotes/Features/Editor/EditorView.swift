import SwiftUI
import UniformTypeIdentifiers
import PencilKit
import PhotosUI
import AVFoundation
import VisionKit
import NeuralNotesCore

private enum EditorPanel: String, Identifiable {
    case elements, audio, search, study, crop, pages, practice, storage, paper, workspace
    var id: String { rawValue }
}

private struct PhotoCropPresentation: Identifiable {
    let id = UUID()
    let image: UIImage
    let pageID: UUID
    let imageID: UUID?
    let data: Data?
    let crop: NormalizedCrop
    /// "Foto e chiedi": the chosen part goes to the Lens, not onto the page.
    var lens = false
}

@MainActor
struct EditorView: View {
    @Bindable var model: EditorViewModel
    let notebook: Notebook
    let library: LibraryViewModel
    var returnToLibrary: (() async -> Void)? = nil
    var notebookSwitching: NotebookSwitching? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: EditorPanel?
    @State private var importing = false
    @State private var importKind = "pdf"
    @State private var working = false
    @State private var confirmDelete = false
    @State private var jumpingToPage = false
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var media: EditorMedia?
    @State private var pendingPhoto: Data?
    @State private var pendingScan: VNDocumentCameraScan?
    @State private var mediaError: String?
    @State private var sideOpen = false
    @State private var sidePDF = false
    @State private var askAboutPhoto = false
    @State private var photoCrop: PhotoCropPresentation?
    @AppStorage(LensSettings.floatingKey) private var lensFloating = false
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("editor.focus") private var focus = false

    var body: some View {
        NavigationStack {
            presentations
                .inspector(isPresented: $sideOpen) { studyInspector }
                .onChange(of: model.lensRequest) { _, _ in sidePDF = false; sideOpen = true }
                .onChange(of: model.lensPanelRequest) { _, _ in lensPanelRequested() }
                .onChange(of: model.objectEditorRequest) { _, _ in panel = .elements }
                .onChange(of: model.searchRequest) { _, _ in panel = .search }
                .onChange(of: model.focusRequest) { _, _ in focus.toggle() }
                .onChange(of: model.lensPick) { _, _ in model.refreshLensOverlays() }
                .onChange(of: model.lensHighlight) { _, _ in model.refreshLensOverlays() }
                .onChange(of: model.lensNoteFocus) { _, _ in model.refreshLensOverlays() }
        }
    }

    // The editor is built from a few small parts, so the type checker of Swift
    // Playgrounds handles each one quickly: page and bars, toolbar and lifecycle, sheets.
    private var editorStack: some View {
        VStack(spacing: 0) {
            if model.page != nil {
                writingSurface
            } else { ProgressView("Apertura pagine…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if !focus && model.currentWorkspace.showPages { pageStrip }
            else if !focus && model.currentWorkspace.showStatus {
                saveStatus.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: focus)
        .overlay { FocusControl(model: model, focus: $focus).allowsHitTesting(!model.navigating && !working && model.hasLease) }
        .overlay(alignment: .topLeading) { recordingBadge }
        .toolbar(focus ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(focus)
        .navigationTitle(notebook.title)
        .onAppear { model.backupMetadata = notebook }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var saveStatus: some View {
        EditorSaveStatus(message: model.status, dirty: model.dirty, busy: working || model.saving || model.navigating) {
            Task { _ = await model.flush() }
        }
    }

    @ViewBuilder private var recordingBadge: some View {
        if let audio = model.audio, audio.recording || audio.transcribingSessionID != nil {
            RecordingIndicator(audio: audio) { panel = .audio }.padding(12)
        }
    }

    private var lifecycle: some View {
        editorStack
            .toolbar { editorToolbar }
            .task { library.markOpened(notebook); model.lensSubject = notebook.title; await model.open() }
            .interactiveDismissDisabled()
            .fullScreenCover(item: $media, onDismiss: finishMediaImport) { source in mediaCapture(source) }
            .onChange(of: model.tool) { _, _ in model.restoreToolPalette(); model.configureTool() }
            .onChange(of: model.ink) { _, _ in model.configureTool() }
            .onChange(of: model.thickness) { _, _ in model.configureTool() }
            .onChange(of: model.fingerDrawing) { _, _ in model.configureTool() }
            .onChange(of: scenePhase) { _, phase in sceneChanged(phase) }
    }

    private var presentations: some View {
        lifecycle
            .alert("NeuralNotes", isPresented: errorShown) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Eliminare questa pagina?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina pagina", role: .destructive) { Task { await model.deletePage() } }
            } message: { Text("La pagina verrà rimossa dal quaderno. I file vengono conservati per il recupero.") }
            .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in imported(result) }
            .sheet(item: $panel) { item in panelSheet(item) }
            .sheet(item: $photoCrop) { request in photoCropSheet(request) }
            .sheet(isPresented: $sharing) { if let shareURL { ShareDocument(url: shareURL) } }
            .sheet(item: $model.lensNoteEditor) { target in LensNoteEditor(model: model, noteID: target.id) }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { libraryButton }
        if let notebookSwitching {
            ToolbarItem(placement: .principal) { NotebookSwitcher(title: notebook.title, switching: notebookSwitching) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.fitPageRequest += 1 } label: { Label("Pagina intera", systemImage: "arrow.up.left.and.arrow.down.right") }
                .accessibilityIdentifier("editorFitPage")
                .disabled(model.navigating)
            navigationMenu
            Button { panel = .paper } label: { Label("Carta e formato", systemImage: "doc.text") }
                .disabled(!model.hasLease || working || model.loading || model.navigating)
            Button { Task { if await model.flush() { panel = .pages } } } label: { Label("Pagine", systemImage: "square.grid.2x2") }
                .disabled(model.navigating || !model.hasLease)
            audioButton
            Button { panel = .study } label: { Label("Studia", systemImage: "sparkles") }
            Button { toggleSidePDF() } label: { Label("PDF affiancato", systemImage: "rectangle.split.2x1") }
            lensMenu
            actionsMenu
        }
    }

    private var libraryButton: some View {
        Button("Libreria", systemImage: "chevron.backward") { Task { await returnToLibraryNow() } }
            .disabled(working || model.loading || model.navigating).accessibilityIdentifier("editorReturnToLibrary")
    }

    private func returnToLibraryNow() async {
        if let returnToLibrary { await returnToLibrary(); return }
        guard await model.close() else { return }
        library.didEdit(notebook)
        dismiss()
    }

    private var navigationMenu: some View {
        Menu {
            Picker("Navigazione", selection: $model.pageNavigation) {
                ForEach(PageNavigationMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.icon).tag(mode) }
            }.pickerStyle(.inline)
        } label: { Label("Navigazione pagine", systemImage: model.pageNavigation.icon) }
            .accessibilityIdentifier("editorPageNavigation")
            .disabled(model.navigating || model.interactionBusy)
    }

    private var audioButton: some View {
        let recording = model.audio?.recording == true
        let title: String = recording ? "REC" : "Audio"
        let icon: String = recording ? "record.circle.fill" : "waveform"
        let tint: Color = recording ? Color.red : Brand.accent
        return Button { panel = .audio } label: { Label(title, systemImage: icon).foregroundStyle(tint) }
            .disabled(!model.hasLease).accessibilityIdentifier("editorAudio")
    }

    private func toggleSidePDF() {
        if sidePDF { sideOpen.toggle() } else { sidePDF = true; sideOpen = true }
    }

    /// The Lens is a tool: underline, circle or tap on the page. A long press opens
    /// the notes, the page chat and the last conversation (⌘K also toggles the tool).
    private var lensMenu: some View {
        let title: String = model.tool == .lens ? "Esci dalla Lente AI" : "Lente AI"
        return Menu {
            Button("Note della Lente", systemImage: "list.bullet.rectangle.portrait") { model.showLensPanel(.notes) }
            Button("Ultima conversazione", systemImage: "bubble.left.and.text.bubble.right") { model.showLensPanel(.selection) }
                .disabled(model.lensSession == nil)
            Button("Chat sulla pagina", systemImage: "doc.text.magnifyingglass") { openLensChat() }
        } label: {
            Label(title, systemImage: "sparkle.magnifyingglass")
        } primaryAction: { toggleLens() }
            .accessibilityIdentifier("editorLens")
    }

    private func toggleLens() {
        let next: WorkspaceTool = model.tool == .lens ? .pen : .lens
        model.chooseTool(next)
    }

    private var actionsMenu: some View {
        Menu {
            Button("Workspace e preferiti", systemImage: "slider.horizontal.3") { panel = .workspace }
            Toggle("Navigatore zoom", systemImage: "viewfinder", isOn: $model.showZoomNavigator)
            Toggle("Puntatore laser", systemImage: "scope", isOn: laserBinding).disabled(model.interactionBusy)
            insertMenu
            documentMenu
            studyMenu
            exportMenu
        } label: { Label("Azioni", systemImage: "ellipsis.circle") }
            .disabled(working || model.loading || model.navigating || !model.hasLease)
    }

    private var laserBinding: Binding<Bool> {
        Binding(get: { model.laserActive }, set: { model.setLaserActive($0) })
    }

    private var insertMenu: some View {
        Menu("Inserisci", systemImage: "plus.circle") {
            Button("Testi e immagini", systemImage: "textformat") { panel = .elements }
            Button("Scatta foto", systemImage: "camera") { Task { await openCamera() } }
            Button("Scansiona documento", systemImage: "doc.viewfinder") { Task { await openMedia(.scanner) } }
            Button("Inserisci da Foto", systemImage: "photo.on.rectangle") { media = .photos }
            Button("Importa immagine", systemImage: "photo") { startImport("image") }
            Button("Importa PDF", systemImage: "doc.badge.plus") { startImport("pdf") }
            Button("Aggiungi pagine da un backup", systemImage: "doc.on.doc") { startImport("native") }
            Button("Aggiungi allegato", systemImage: "paperclip") { startImport("attachment") }
        }
    }

    private func startImport(_ kind: String) { importKind = kind; importing = true }

    private var documentMenu: some View {
        Menu("Documento", systemImage: "book.closed") {
            Button("Carta e formato", systemImage: "doc.text") { panel = .paper }
            Button("Spazio e recupero", systemImage: "externaldrive") { panel = .storage }
            Button("Cerca nel documento", systemImage: "magnifyingglass") { panel = .search }
            Button("Salva adesso", systemImage: "checkmark.circle") { Task { _ = await model.flush() } }
            Button("Nuova finestra", systemImage: "macwindow.badge.plus") { openNewWindow() }
        }
    }

    private func openNewWindow() {
        if UIApplication.shared.supportsMultipleScenes { openWindow(id: "library") }
        else { model.error = "Più finestre non disponibili in questa esecuzione." }
    }

    private var studyMenu: some View {
        Menu("Studio e riconoscimento", systemImage: "sparkles") {
            Button("Flashcard e ripasso", systemImage: "rectangle.stack") { panel = .practice }
            Button("Riconosci testo pagina", systemImage: "text.viewfinder") { Task { await recognize() } }
            Button("Riconosci un’area", systemImage: "crop") { panel = .crop }
        }
    }

    private var exportMenu: some View {
        Menu("Esporta", systemImage: "square.and.arrow.up") {
            Button("PDF vettoriale", systemImage: "doc") { Task { await export(native: false) } }
            Button("PDF con aspetto PencilKit", systemImage: "paintbrush") { Task { await export(native: false, vector: false) } }
            Button("Quaderno nativo e backup", systemImage: "externaldrive") { Task { await export(native: true) } }
            Button("Pagina PNG", systemImage: "photo") { Task { await exportExtra("png") } }
            Button("Pagina JPEG", systemImage: "photo") { Task { await exportExtra("jpeg") } }
            Button("Area selezionata PNG", systemImage: "selection.pin.in.out") { Task { await exportExtra("selection") } }
                .disabled(model.selectionBounds.isNull)
            Button("Appunti Markdown", systemImage: "text.document") { Task { await exportExtra("markdown") } }
            Button("Appunti testo", systemImage: "text.alignleft") { Task { await exportExtra("text") } }
            Button("Raccolta evidenziazioni PDF", systemImage: "highlighter") { Task { await exportExtra("highlights") } }
            Button("Stampa", systemImage: "printer") { Task { await exportExtra("print") } }
        }
    }

    @ViewBuilder private func mediaCapture(_ source: EditorMedia) -> some View {
        switch source {
        case .photos:
            PhotoLibraryImport { result in
                switch result { case .success(let data): pendingPhoto = data; case .failure(let error): mediaError = error.localizedDescription }
                media = nil
            }
        case .camera:
            CameraCapture { image in pendingPhoto = image?.jpegData(compressionQuality: 0.92); media = nil }
        case .scanner:
            DocumentScanner { result in
                switch result { case .success(let scan): pendingScan = scan; case .failure(let error): mediaError = error.localizedDescription }
                media = nil
            }
        }
    }

    private func sceneChanged(_ phase: ScenePhase) {
        if phase != .active {
            Task {
                let identifier = UIApplication.shared.beginBackgroundTask(withName: "Salvataggio NeuralNotes")
                _ = await model.flush()
                model.audio?.transcriptionTask?.cancel()
                await model.audio?.checkpointRecording()
                if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
            }
        } else { Task { await model.audio?.refreshRecordingAfterForeground() } }
    }

    private func imported(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): Task { await importFile(url) }
        case .failure(let error): model.error = error.localizedDescription
        }
    }

    @ViewBuilder private func panelSheet(_ item: EditorPanel) -> some View {
        switch item {
        case .workspace: WorkspacePanel(model: model)
        case .paper: PageTemplatePanel(model: model)
        case .storage: StoragePanel(workspace: model.workspace, editor: model, metadata: notebook)
        case .pages: PageBrowser(model: model)
        case .practice: PracticePanel(model: model, notebook: notebook)
        case .elements: ElementEditor(model: model)
        case .audio:
            if let audio = model.audio { AudioPanel(audio: audio, model: model) }
        case .search: DocumentSearchPanel(model: model)
        case .study: StudyPanel(model: model, notebook: notebook, library: library)
        case .crop:
            if let page = model.page { areaRecognition(page) }
        }
    }

    private func areaRecognition(_ page: PageSnapshot) -> some View {
        let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace)
        return AreaRecognitionPanel(image: image, workspace: model.workspace, pageID: page.id) { text in
            model.page?.recognizedText += "\n" + text; model.drawingChanged()
        }
    }

    private func photoCropSheet(_ request: PhotoCropPresentation) -> some View {
        let title: String = request.lens ? "Cosa vuoi chiedere?" : "Ritaglia foto"
        let confirm: String = request.lens ? "Chiedi alla Lente" : "Usa ritaglio"
        let hint: String = request.lens ? Self.lensCropHint : Self.photoCropHint
        return PhotoCropPanel(image: request.image, initial: request.crop, title: title, confirm: confirm, hint: hint) { crop in
            finishPhotoCrop(request, crop)
        }
    }

    private static let lensCropHint = "Trascina un rettangolo sulla parte da chiedere (una formula, un grafico, un paragrafo). «Tutto» usa la foto intera."
    private static let photoCropHint = "Trascina per scegliere l’area. L’immagine originale rimane conservata."

    private func finishPhotoCrop(_ request: PhotoCropPresentation, _ crop: NormalizedCrop) {
        if request.lens {
            // A tap without a drag selects almost nothing: then the whole photo is asked about.
            let tiny = crop.width < 0.03 || crop.height < 0.03
            let chosen: NormalizedCrop = tiny ? .full : crop
            model.lensAnchor = nil
            model.openLens(LensCardRequest(photo: request.data, photoCrop: chosen))
            return
        }
        guard model.page?.id == request.pageID else { model.error = "La pagina di destinazione è cambiata. Riprova l’inserimento."; return }
        if let imageID = request.imageID { model.selectedObjectID = imageID; model.cropSelectedImage(crop) }
        else if let data = request.data { Task { await insertPhoto(data: data, crop: crop, pageID: request.pageID) } }
    }

    private func lensPanelRequested() {
        // The conversation shows in the floating window when the student chose it;
        // with the PDF beside the notebook it opens under the PDF.
        if model.lensTab == .selection && lensFloating { return }
        if model.lensTab != .selection { sidePDF = false }
        sideOpen = true
    }

    private var writingSurface: some View {
        DocumentPageViewport(model: model)
            .allowsHitTesting(model.hasLease && !model.loading && !model.navigating && !working)
            .onDrop(of: [.pdf, .image, .text, .url, .fileURL], isTargeted: nil) { providers, location in dropped(providers, at: location) }
            .overlay(alignment: toolbarAlignment) { toolbarLayer }
            .overlay { floatingLens }
            .overlay(alignment: .bottom) {
                if model.currentWorkspace.showStatus { EditorActivityFeedback(message: model.status) }
            }
    }

    private func dropped(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        let host = model.pagePresenter as? CanvasHost
        let point = host?.surface.convert(location, from: host) ?? location
        Task { await PageDrop.insert(providers, at: point, model: model) }
        return model.hasLease
    }

    @ViewBuilder private var toolbarLayer: some View {
        if !focus { floatingToolbar.transition(.opacity.combined(with: .scale(scale: 0.96))) }
    }

    /// The floating Lens window: it can be dragged and docked again on the right.
    @ViewBuilder private var floatingLens: some View {
        if lensFloating, !focus, let session = model.lensSession {
            LensFloatingCard(model: model, session: session, dock: dockLens, insertPhoto: insertLensPhoto)
        }
    }

    private func openLensChat() { sidePDF = false; sideOpen = true; model.requestLens() }
    private func dockLens() { lensFloating = false; sidePDF = false; model.showLensPanel(.selection) }
    private func undockLens() {
        lensFloating = true
        if !sidePDF { sideOpen = false }
    }
    private func lensPhoto(_ source: EditorMedia) {
        guard media == nil, photoCrop == nil else { return }
        askAboutPhoto = true
        if source == .photos { media = .photos; return }
        // Without camera access nothing opens: the next ordinary photo must not go to the Lens.
        Task { await openCamera(); if media == nil { askAboutPhoto = false } }
    }
    private func insertLensPhoto(_ data: Data, _ crop: NormalizedCrop) {
        guard let pageID = model.page?.id else { return }
        Task { await insertPhoto(data: data, crop: crop, pageID: pageID) }
    }
    private var toolbarAlignment: Alignment {
        switch model.currentWorkspace.dock { case .top: return .top; case .bottom: return .bottom; case .leading: return .leading; case .trailing: return .trailing }
    }
    private var studyInspector: some View {
        Group {
            if sidePDF { pdfInspector }
            else { LensSidePanel(model: model, notebook: notebook, close: { sideOpen = false }, undock: undockLens, insertPhoto: insertLensPhoto) }
        }.inspectorColumnWidth(min: 320, ideal: 400, max: 600)
    }
    private var pdfInspector: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Button("Chiudi pannello", systemImage: "xmark") { sideOpen = false }.accessibilityIdentifier("closeStudyInspector") }
                .padding(.horizontal).padding(.vertical, 8)
            PDFStudyPanel(model: model)
            // A question about the PDF opens under it, so the PDF stays in view.
            if !lensFloating, let session = model.lensSession { pdfLens(session) }
        }
    }
    private func pdfLens(_ session: LensSession) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.subheadline.bold())
                Spacer()
                Button(action: undockLens) { Image(systemName: "rectangle.on.rectangle") }.accessibilityLabel("Finestra mobile")
                Button { model.closeLensSession() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Chiudi la conversazione")
            }.padding(.horizontal, 12).padding(.vertical, 6)
            LensSessionView(model: model, session: session, insertPhoto: insertLensPhoto).id(session.id).frame(height: 360)
        }
    }
    private var floatingToolbar: some View {
        let dock = model.currentWorkspace.dock
        let along: CGFloat = dock.vertical ? 72 : 12
        let trailing: CGFloat = dock.vertical ? 0 : 60
        let top: CGFloat = model.audio?.recording == true && dock == .top ? 42 : 0
        return EditorQuickToolbar(model: model, photo: { media = .photos }, camera: { Task { await openCamera() } },
                                  text: startTyping, edit: { panel = .elements }, crop: { openImageCrop() }, workspace: { panel = .workspace }, lens: lensActions)
            .disabled(!model.hasLease || model.loading || model.navigating || working)
            .padding(.horizontal, 12).padding(.vertical, along).padding(.trailing, trailing).padding(.top, top)
    }
    private func startTyping() { model.chooseTool(.text); model.beginTextEdit(at: CGPoint(x: 48, y: 96)) }
    private var lensActions: LensBarActions {
        LensBarActions(photo: { lensPhoto(.camera) }, library: { lensPhoto(.photos) }, notes: { model.showLensPanel(.notes) }, chat: { openLensChat() })
    }

    private var pageIndex: Int { model.pages.firstIndex(where: { $0.id == model.page?.id }) ?? 0 }
    private var pageNavigationBusy: Bool {
        working || model.loading || model.saving || model.navigating || !model.hasLease || model.hasActiveStroke
    }

    private var pageStrip: some View {
        GeometryReader { geometry in
            pageControls(showSteps: geometry.size.width >= 500)
        }
        .frame(maxWidth: 760).frame(height: 48)
        .padding(.horizontal, 8).frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorPageStrip")
        .disabled(pageNavigationBusy || model.pages.isEmpty)
    }

    private func pageControls(showSteps: Bool) -> some View {
        HStack(spacing: 0) {
            if model.currentWorkspace.showStatus { saveStatus }
            if showSteps { pageStep(-1) }
            Button { jumpingToPage = true } label: {
                Text("\(pageIndex + 1) / \(model.pages.count)").font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 64, minHeight: 44)
            }
            .accessibilityLabel("Vai alla pagina")
            .accessibilityValue("Pagina \(pageIndex + 1) di \(model.pages.count)")
            .accessibilityIdentifier("editorPageCounter")
            .popover(isPresented: $jumpingToPage) {
                PageJumpPopover(count: model.pages.count, currentIndex: pageIndex, select: selectPage)
            }
            EditorPageScrubber(pageIDs: model.pages.map(\.id), currentIndex: pageIndex, select: selectPage)
                .padding(.horizontal, 4)
            if showSteps { pageStep(1) }
            Button { Task { await model.addPage() } } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }.accessibilityLabel("Aggiungi pagina").accessibilityIdentifier("editorAddPage")
            pageActions
        }
        .buttonStyle(.plain).foregroundStyle(Brand.accent)
        .frame(height: 48)
    }

    private func pageStep(_ offset: Int) -> some View {
        Button { selectPage(pageIndex + offset) } label: {
            Image(systemName: offset < 0 ? "chevron.backward" : "chevron.forward")
                .font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(offset < 0 ? "Pagina precedente" : "Pagina successiva")
        .accessibilityIdentifier(offset < 0 ? "editorPreviousPage" : "editorNextPage")
        .disabled(offset < 0 ? pageIndex == 0 : pageIndex >= model.pages.count - 1)
    }

    private var pageActions: some View {
        Menu {
            Button("Tutte le pagine", systemImage: "square.grid.2x2") {
                Task { if await model.flush() { panel = .pages } }
            }
            Divider()
            Button("Pagina bianca dopo questa", systemImage: "doc.badge.plus") { Task { await model.insertBlankPageAfterCurrent() } }
            Button("Duplica pagina", systemImage: "doc.on.doc") { Task { await model.duplicatePage() } }
            Button("Sposta indietro", systemImage: "arrow.backward") { Task { await movePage(-1) } }.disabled(pageIndex == 0)
            Button("Sposta avanti", systemImage: "arrow.forward") { Task { await movePage(1) } }.disabled(pageIndex >= model.pages.count - 1)
            Divider()
            Button("Elimina pagina", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Azioni pagina").accessibilityIdentifier("editorPageActions")
    }

    private func selectPage(_ index: Int) {
        guard !pageNavigationBusy, model.pages.indices.contains(index), index != pageIndex else { return }
        let destination = model.pages[index]
        Task { await model.select(destination) }
    }

    private var importTypes: [UTType] {
        importKind == "pdf" ? [.pdf] : importKind == "image" ? [.image] : importKind == "native" ? [.data, .folder, .package] : [.data]
    }

    private func importFile(_ url: URL) async {
        working = true; defer { working = false }
        if importKind == "native" || importKind == "pdf" {
            await model.importPages(from: url, native: importKind == "native"); return
        }
        guard await model.flush() else { return }
        do {
            switch importKind {
            case "image":
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                preparePhoto(try DocumentServices.boundedRead(url))
            default: try await DocumentServices.importAttachment(from: url, into: model.workspace)
            }
        } catch { model.error = error.localizedDescription }

    }

    private func recognize() async {
        guard let page = model.page else { return }
        working = true; defer { working = false }
        do {
            guard let data = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace).pngData() else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
            model.page?.recognizedText = text; model.drawingChanged()
            model.error = text.isEmpty ? "Non è stato riconosciuto testo in questa pagina." : "Testo riconosciuto e disponibile nella ricerca del documento."
        } catch { model.error = error.localizedDescription }
    }

    private func export(native: Bool, vector: Bool = true) async {
        working = true; defer { working = false }
        guard await model.flush() else { return }
        if model.audio?.recording == true { await model.audio?.pause(reason: "Esportazione") }
        do {
            shareURL = native ? try await model.workspace.exportNative(metadata: notebook)
                              : try await DocumentServices.exportPDF(workspace: model.workspace, vectorInk: vector)
            sharing = true
        } catch { model.error = error.localizedDescription }
    }

    private func movePage(_ offset: Int) async {
        guard let page = model.page, await model.flush() else { return }
        var ids = model.pages.map(\.id)
        guard let from = ids.firstIndex(of: page.id) else { return }
        let to = max(0, min(ids.count - 1, from + offset))
        ids.remove(at: from); ids.insert(page.id, at: to); await model.reorder(ids)
    }
    private func exportExtra(_ kind: String) async {
        working = true; defer { working = false }
        guard await model.flush() else { return }
        do {
            let url: URL
            switch kind {
            case "png", "jpeg", "selection": url = try model.exportPageImage(jpeg: kind == "jpeg", selection: kind == "selection")
            case "print": url = try await DocumentServices.exportPDF(workspace: model.workspace)
            default: url = try await model.exportNotebookText(markdown: kind != "text", highlightsOnly: kind == "highlights")
            }
            if kind == "print", let anchor = model.pagePresenter as? UIView {
                let controller = UIPrintInteractionController.shared, info = UIPrintInfo(dictionary: nil)
                info.jobName = notebook.title; info.outputType = .general
                controller.printInfo = info; controller.printingItem = url
                controller.present(from: CGRect(x: max(0, anchor.bounds.width - 44), y: 0, width: 44, height: 44), in: anchor, animated: true, completionHandler: nil)
            } else { shareURL = url; sharing = true }
        } catch { model.error = error.localizedDescription }
    }


    private func preparePhoto(_ data: Data) {
        guard let image = try? DocumentServices.photoPreview(data) else { model.error = "Immagine non leggibile o troppo grande."; return }
        guard let pageID = model.page?.id else { return }
        photoCrop = PhotoCropPresentation(image: image, pageID: pageID, imageID: nil, data: data, crop: .full)
    }
    private func prepareLensPhoto(_ data: Data) {
        guard let image = try? DocumentServices.photoPreview(data) else { model.error = "Immagine non leggibile o troppo grande."; return }
        photoCrop = PhotoCropPresentation(image: image, pageID: model.page?.id ?? UUID(), imageID: nil, data: data, crop: .full, lens: true)
    }
    private func openImageCrop() {
        guard model.selectedIDs.count == 1, let item = model.page?.images.first(where: { $0.id == model.selectedObjectID }),
              let image = UIImage(contentsOfFile: model.workspace.package.appendingPathComponent(item.file).path) else {
            model.error = "Seleziona una sola immagine da ritagliare."; return
        }
        guard let pageID = model.page?.id else { return }
        photoCrop = PhotoCropPresentation(image: image, pageID: pageID, imageID: item.id, data: nil, crop: item.crop ?? .full)
    }
    private func insertPhoto(data: Data, crop: NormalizedCrop, pageID: UUID) async {
        guard model.page?.id == pageID, model.hasLease, !model.hasActiveStroke else { return }
        working = true; defer { working = false }
        do {
            var element = try await DocumentServices.importImage(data: data, into: model.workspace)
            guard model.page?.id == pageID, model.hasLease, !model.hasActiveStroke else { model.error = "La pagina di destinazione è cambiata: la foto non è stata inserita su un altro foglio."; return }
            let ratio = element.height / element.width * crop.height / crop.width
            element.width = min(element.width, max(40, ((model.page?.height ?? 1024) - 160) / ratio))
            element.height = element.width * ratio; element.crop = crop
            model.addImage(element)
        } catch { model.error = error.localizedDescription }
    }
    private func openCamera() async { await openMedia(.camera) }
    private func openMedia(_ source: EditorMedia) async {
        guard media == nil, panel == nil, photoCrop == nil, !working else { return }
        do { try await CameraAccess.request(scanner: source == .scanner); media = source }
        catch { model.error = error.localizedDescription }
    }
    private func finishMediaImport() {
        if let error = mediaError { mediaError = nil; model.error = error }
        if let data = pendingPhoto {
            pendingPhoto = nil
            // "Foto e chiedi" from the Lens: crop the part to ask about; the photo goes onto the page only if wanted.
            if askAboutPhoto { askAboutPhoto = false; prepareLensPhoto(data) }
            else { preparePhoto(data) }
        } else { askAboutPhoto = false }
        if let scan = pendingScan {
            pendingScan = nil
            Task { working = true; defer { working = false }; await model.importScan(scan) }
        }
    }

}

@MainActor
struct ShareDocument: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
