import SwiftUI
import UniformTypeIdentifiers
import PencilKit
import PhotosUI
import AVFoundation
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var camera = false
    @State private var captured: UIImage?
    @State private var cropImage: UIImage?
    @State private var insertingImage = false
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("editor.focus") private var focus = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.page != nil {
                    DocumentPageViewport(model: model).allowsHitTesting(model.hasLease && !model.loading && !model.navigating && !working)
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
                    }.disabled(working || model.loading || model.navigating)
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
                    Menu {
                        Button("Workspace e preferiti", systemImage: "slider.horizontal.3") { panel = .workspace }
                        Menu("Inserisci", systemImage: "plus.circle") {
                            Button("Testi e immagini", systemImage: "textformat") { panel = .elements }
                            Button("Scatta foto", systemImage: "camera") { Task { await openCamera() } }
                            PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Inserisci da Foto", systemImage: "photo.on.rectangle") }
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
                        }
                    } label: { Label("Azioni", systemImage: "ellipsis.circle") }
                    .disabled(working || model.loading || model.navigating || !model.hasLease)
                }
            }
            .task { library.markOpened(notebook); await model.open() }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                working = true; defer { working = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                    preparePhoto(data)
                } catch is CancellationError { }
                catch { model.error = error.localizedDescription }
            }
            .interactiveDismissDisabled()
            .photosPicker(isPresented: $choosingPhoto, selection: $selectedPhoto, matching: .images)
            .fullScreenCover(isPresented: $camera, onDismiss: {
                if let image = captured, let data = image.jpegData(compressionQuality: 0.92) { captured = nil; preparePhoto(data) }
            }) { CameraCapture { image in captured = image; camera = false } }
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
                case .storage: StoragePanel(workspace: model.workspace, editor: model)
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
        }
    }

    private var toolbarAlignment: Alignment {
        switch model.currentWorkspace.dock { case .top: return .top; case .bottom: return .bottom; case .leading: return .leading; case .trailing: return .trailing }
    }
    private var floatingToolbar: some View {
        EditorQuickToolbar(model: model, photo: { choosingPhoto = true }, camera: { Task { await openCamera() } },
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
        guard await model.flush() else { return }
        let before = model.pages.map(\.id), selectedBefore = model.page?.id
        do {
            switch importKind {
            case "native":
                if model.audio?.recording == true { await model.audio?.pause(reason: "Importazione pagine") }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let pages = try await model.workspace.appendNative(from: url)
                if let page = pages.first { await model.select(page) }
            case "pdf":
                let pages = try await DocumentServices.importPDF(from: url, into: model.workspace)
                if let page = pages.first { await model.select(page) }
            case "image":
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                preparePhoto(try DocumentServices.boundedRead(url))
            default: try await DocumentServices.importAttachment(from: url, into: model.workspace)
            }
        } catch { model.error = error.localizedDescription }
        if importKind == "native" || importKind == "pdf" {
            // PDF import may retain successfully added pages after a later
            // failure. Include those in history as well as successful imports.
            do {
                model.pages = try await model.workspace.pages()
                model.recordOrder(before, selectedBefore: selectedBefore, label: "Importa pagine")
            } catch { model.error = error.localizedDescription }
        }
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
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.error = "Fotocamera non disponibile su questo dispositivo."; return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            model.error = "Abilita Fotocamera nelle funzionalità del progetto Swift Playground."; return
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else { model.error = "Consenti l’accesso alla fotocamera nelle impostazioni dell’iPad."; return }
        camera = true
    }
}

@MainActor
struct ShareDocument: UIViewControllerRepresentable {
    let url: URL
    var accessibilityID: String? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.view.accessibilityIdentifier = accessibilityID
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
