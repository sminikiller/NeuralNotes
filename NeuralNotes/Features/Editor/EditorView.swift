import SwiftUI
import UniformTypeIdentifiers
import PencilKit
import PhotosUI
import AVFoundation
import VisionKit
import NeuralNotesCore

private enum EditorPanel: String, Identifiable {
    case elements, audio, search, study, crop, pages, practice, photoCrop, storage, paper, workspace
    var id: String { rawValue }
}

@MainActor
struct EditorView: View {
    @Bindable var model: EditorViewModel
    let notebook: Notebook
    let library: LibraryViewModel
    var returnToLibrary: (() async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: EditorPanel?
    @State private var importing = false
    @State private var importKind = "pdf"
    @State private var working = false
    @State private var confirmDelete = false
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var media: EditorMedia?
    @State private var pendingPhoto: Data?
    @State private var pendingScan: VNDocumentCameraScan?
    @State private var mediaError: String?
    @State private var sideOpen = false
    @State private var lensPopup = false
    @State private var sidePDF = false
    @State private var cropImage: UIImage?
    @State private var insertingImage = false
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("editor.focus") private var focus = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.page != nil {
                    DocumentPageViewport(model: model).allowsHitTesting(model.hasLease && !model.loading && !model.navigating && !working)
                        .popover(isPresented: $lensPopup, attachmentAnchor: .point(.topTrailing)) {
                            VStack(spacing: 8) {
                                HStack {
                                    Button("Apri pannello", systemImage: "sidebar.right") { lensPopup = false; sidePDF = false; sideOpen = true }
                                    Spacer(); Button("Chiudi", systemImage: "xmark") { lensPopup = false }
                                }.font(.caption).padding(.horizontal).padding(.top, 12)
                                LensPanel(model: model, notebook: notebook)
                            }.frame(width: 360, height: 520).accessibilityIdentifier("lensQuickPopup")
                        }
                        .onDrop(of: [.pdf, .image, .text, .url, .fileURL], isTargeted: nil) { providers, location in
                            let point = (model.pagePresenter as? CanvasHost)?.surface.convert(location, from: model.pagePresenter as? CanvasHost) ?? location
                            Task { await PageDrop.insert(providers, at: point, model: model) }; return model.hasLease
                        }
                        .overlay(alignment: toolbarAlignment) {
                            if !focus { floatingToolbar.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                        }
                } else { ProgressView("Apertura pagine…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                if !focus && model.currentWorkspace.showPages { pageStrip }
                if !focus && model.currentWorkspace.showStatus { HStack {
                    Image(systemName: model.dirty ? "circle.dotted" : "checkmark.circle")
                    Text(model.status)
                    Spacer()
                    if model.audio?.recording == true { Label("REC", systemImage: "record.circle.fill").foregroundStyle(.red) }
                    if working || model.saving { ProgressView().controlSize(.small) }
                }
                .font(.caption).padding(.horizontal).padding(.vertical, 6).background(.bar) }
            }
            .animation(.easeInOut(duration: 0.25), value: focus)
            .overlay { FocusControl(model: model, focus: $focus).allowsHitTesting(!model.navigating && !working && model.hasLease) }
            .overlay(alignment: .topLeading) {
                if let audio = model.audio, audio.recording || audio.transcribingSessionID != nil {
                    RecordingIndicator(audio: audio) { panel = .audio }.padding(12)
                }
            }
            .toolbar(focus ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(focus)
            .navigationTitle(notebook.title)
            .onAppear { model.backupMetadata = notebook }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Libreria", systemImage: "chevron.backward") {
                        Task {
                            if let returnToLibrary { await returnToLibrary(); return }
                            guard await model.close() else { return }
                            library.didEdit(notebook)
                            dismiss()
                        }
                    }.disabled(working || model.loading || model.navigating).accessibilityIdentifier("editorReturnToLibrary")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.fitPageRequest += 1 } label: { Label("Pagina intera", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .accessibilityIdentifier("editorFitPage")
                        .disabled(model.navigating)
                    Menu {
                        Picker("Navigazione", selection: $model.pageNavigation) {
                            ForEach(PageNavigationMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.icon).tag(mode) }
                        }.pickerStyle(.inline)
                    } label: { Label("Navigazione pagine", systemImage: model.pageNavigation.icon) }
                        .accessibilityIdentifier("editorPageNavigation")
                        .disabled(model.navigating || model.interactionBusy)
                    Button { panel = .paper } label: { Label("Carta e formato", systemImage: "doc.text") }
                        .disabled(!model.hasLease || working || model.loading || model.navigating)
                    Button { Task { if await model.flush() { panel = .pages } } } label: { Label("Pagine", systemImage: "square.grid.2x2") }
                        .disabled(model.navigating || !model.hasLease)
                    Button { panel = .audio } label: {
                        Label(model.audio?.recording == true ? "REC" : "Audio", systemImage: model.audio?.recording == true ? "record.circle.fill" : "waveform")
                            .foregroundStyle(model.audio?.recording == true ? Color.red : Brand.accent)
                    }.disabled(!model.hasLease).accessibilityIdentifier("editorAudio")
                    Button { panel = .study } label: { Label("Studia", systemImage: "sparkles") }
                    Button { if sidePDF { sideOpen.toggle() } else { sidePDF = true; sideOpen = true } } label: { Label("PDF affiancato", systemImage: "rectangle.split.2x1") }
                    Button { sidePDF = false; sideOpen = true; model.requestLens() } label: { Label("Lente AI", systemImage: "sparkle.magnifyingglass") }.keyboardShortcut("k", modifiers: .command)
                        .accessibilityIdentifier("editorLens")
                    Menu {
                        Button("Workspace e preferiti", systemImage: "slider.horizontal.3") { panel = .workspace }
                        Toggle("Navigatore zoom", systemImage: "viewfinder", isOn: $model.showZoomNavigator)
                        Toggle("Puntatore laser", systemImage: "scope", isOn: Binding(get: { model.laserActive }, set: { model.setLaserActive($0) })).disabled(model.interactionBusy)
                        Menu("Inserisci", systemImage: "plus.circle") {
                            Button("Testi e immagini", systemImage: "textformat") { panel = .elements }
                            Button("Scatta foto", systemImage: "camera") { Task { await openCamera() } }
                            Button("Scansiona documento", systemImage: "doc.viewfinder") { Task { await openMedia(.scanner) } }
                            Button("Inserisci da Foto", systemImage: "photo.on.rectangle") { media = .photos }
                            Button("Importa immagine", systemImage: "photo") { importKind = "image"; importing = true }
                            Button("Importa PDF", systemImage: "doc.badge.plus") { importKind = "pdf"; importing = true }
                            Button("Aggiungi pagine da un backup", systemImage: "doc.on.doc") { importKind = "native"; importing = true }
                            Button("Aggiungi allegato", systemImage: "paperclip") { importKind = "attachment"; importing = true }
                        }
                        Menu("Documento", systemImage: "book.closed") {
                            Button("Carta e formato", systemImage: "doc.text") { panel = .paper }
                            Button("Spazio e recupero", systemImage: "externaldrive") { panel = .storage }
                            Button("Cerca nel documento", systemImage: "magnifyingglass") { panel = .search }
                            Button("Salva adesso", systemImage: "checkmark.circle") { Task { _ = await model.flush() } }
                            Button("Nuova finestra", systemImage: "macwindow.badge.plus") {
                                if UIApplication.shared.supportsMultipleScenes { openWindow(id: "library") }
                                else { model.error = "Più finestre non disponibili in questa esecuzione." }
                            }
                        }
                        Menu("Studio e riconoscimento", systemImage: "sparkles") {
                            Button("Flashcard e ripasso", systemImage: "rectangle.stack") { panel = .practice }
                            Button("Riconosci testo pagina", systemImage: "text.viewfinder") { Task { await recognize() } }
                            Button("Riconosci un’area", systemImage: "crop") { panel = .crop }
                        }
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
                    } label: { Label("Azioni", systemImage: "ellipsis.circle") }
                    .disabled(working || model.loading || model.navigating || !model.hasLease)
                }
            }
            .task { library.markOpened(notebook); await model.open() }
            .interactiveDismissDisabled()
            .fullScreenCover(item: $media, onDismiss: finishMediaImport) { source in
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
            .onChange(of: model.tool) { _, _ in model.restoreToolPalette(); model.configureTool() }
            .onChange(of: model.ink) { _, _ in model.configureTool() }
            .onChange(of: model.thickness) { _, _ in model.configureTool() }
            .onChange(of: model.fingerDrawing) { _, _ in model.configureTool() }
            .onChange(of: scenePhase) { _, phase in
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
            .alert("NeuralNotes", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Eliminare questa pagina?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina pagina", role: .destructive) { Task { await model.deletePage() } }
            } message: { Text("La pagina verrà rimossa dal quaderno. I file vengono conservati per il recupero.") }
            .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in
                switch result {
                case .success(let url): Task { await importFile(url) }
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .sheet(item: $panel) { item in
                switch item {
                case .workspace: WorkspacePanel(model: model)
                case .paper: PageTemplatePanel(model: model)
                case .storage: StoragePanel(workspace: model.workspace, editor: model, metadata: notebook)
                case .photoCrop:
                    if let cropImage {
                        PhotoCropPanel(image: cropImage, initial: insertingImage ? .full : selectedCrop) { crop in
                            if insertingImage { Task { await insertPhoto(crop) } }
                            else { model.cropSelectedImage(crop) }
                        }
                    }
                case .pages: PageBrowser(model: model)
                case .practice: PracticePanel(model: model, notebook: notebook)
                case .elements: ElementEditor(model: model)
                case .audio:
                    if let audio = model.audio { AudioPanel(audio: audio, model: model) }
                case .search: DocumentSearchPanel(model: model)
                case .study: StudyPanel(model: model, notebook: notebook, library: library)
                case .crop:
                    if let page = model.page {
                        AreaRecognitionPanel(image: DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace),
                            workspace: model.workspace, pageID: page.id) { text in
                            model.page?.recognizedText += "\n" + text; model.drawingChanged()
                        }
                    }
                }
            }
            .sheet(isPresented: $sharing) { if let shareURL { ShareDocument(url: shareURL) } }
            .inspector(isPresented: $sideOpen) {
                studyInspector
            }
            .onChange(of: model.lensRequest) { _, _ in
                sidePDF = false
                if model.lensPrefersPopup { sideOpen = false; lensPopup = true }
                else { lensPopup = false; sideOpen = true }
            }
            .onChange(of: model.objectEditorRequest) { _, _ in panel = .elements }
            .onChange(of: model.searchRequest) { _, _ in panel = .search }
            .onChange(of: model.focusRequest) { _, _ in focus.toggle() }
        }
    }

    private var toolbarAlignment: Alignment {
        switch model.currentWorkspace.dock { case .top: return .top; case .bottom: return .bottom; case .leading: return .leading; case .trailing: return .trailing }
    }
    private var studyInspector: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Button("Chiudi pannello", systemImage: "xmark") { sideOpen = false }.accessibilityIdentifier("closeStudyInspector") }.padding()
            if sidePDF { PDFStudyPanel(model: model) }
            else { LensPanel(model: model, notebook: notebook) }
        }.inspectorColumnWidth(min: 320, ideal: 420, max: 600)
    }
    private var floatingToolbar: some View {
        EditorQuickToolbar(model: model, photo: { media = .photos }, camera: { Task { await openCamera() } },
            text: { model.addText(); panel = .elements }, edit: { panel = .elements }, crop: { openImageCrop() }, workspace: { panel = .workspace })
            .disabled(!model.hasLease || model.loading || model.navigating || working)
            .padding(.horizontal, 12).padding(.vertical, model.currentWorkspace.dock.vertical ? 72 : 12)
            .padding(.trailing, model.currentWorkspace.dock.vertical ? 0 : 60)
            .padding(.top, model.audio?.recording == true && model.currentWorkspace.dock == .top ? 42 : 0)
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { row in
                    Button { Task { await model.select(row.element) } } label: {
                        Text("\(row.offset + 1)").font(.headline.monospacedDigit())
                            .frame(minWidth: 44, minHeight: 44)
                            .background(model.page?.id == row.element.id ? Brand.accent.opacity(0.2) : Brand.background,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityLabel("Pagina \(row.offset + 1)")
                        .accessibilityIdentifier("pageSelect-\(row.offset + 1)")
                        .accessibilityValue(model.page?.id == row.element.id ? "Pagina corrente" : "")
                }
                Button { Task { await model.addPage() } } label: { Label("Pagina", systemImage: "plus") }
                    .accessibilityIdentifier("editorAddPage")
                Menu {
                    Button("Pagina bianca dopo questa") { Task { await model.insertBlankPageAfterCurrent() } }
                    Button("Duplica pagina") { Task { await model.duplicatePage() } }
                    Button("Sposta indietro") { Task { await movePage(-1) } }
                    Button("Sposta avanti") { Task { await movePage(1) } }
                    Button("Elimina pagina", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
            }.padding(.horizontal).padding(.vertical, 6)
        }.background(.bar).disabled(working || model.loading || model.saving || model.navigating || !model.hasLease)
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

    private var selectedCrop: NormalizedCrop { model.page?.images.first(where: { $0.id == model.selectedObjectID })?.crop ?? .full }

    private func preparePhoto(_ data: Data) {
        guard let image = try? DocumentServices.photoPreview(data) else { model.error = "Immagine non leggibile o troppo grande."; return }
        cropImage = image; insertingImage = true; panel = .photoCrop
    }
    private func openImageCrop() {
        guard model.selectedIDs.count == 1, let item = model.page?.images.first(where: { $0.id == model.selectedObjectID }),
              let image = UIImage(contentsOfFile: model.workspace.package.appendingPathComponent(item.file).path) else {
            model.error = "Seleziona una sola immagine da ritagliare."; return
        }
        cropImage = image; insertingImage = false; panel = .photoCrop
    }
    private func insertPhoto(_ crop: NormalizedCrop) async {
        guard let image = cropImage, let data = image.jpegData(compressionQuality: 0.92) else { return }
        working = true; defer { working = false }
        do {
            var element = try await DocumentServices.importImage(data: data, into: model.workspace)
            let ratio = element.height / element.width * crop.height / crop.width
            element.width = min(element.width, max(40, ((model.page?.height ?? 1024) - 160) / ratio))
            element.height = element.width * ratio; element.crop = crop
            model.addImage(element)
        } catch { model.error = error.localizedDescription }
    }
    private func openCamera() async { await openMedia(.camera) }
    private func openMedia(_ source: EditorMedia) async {
        guard media == nil, panel == nil, !working else { return }
        do { try await CameraAccess.request(scanner: source == .scanner); media = source }
        catch { model.error = error.localizedDescription }
    }
    private func finishMediaImport() {
        if let error = mediaError { mediaError = nil; model.error = error }
        if let data = pendingPhoto { pendingPhoto = nil; preparePhoto(data) }
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
