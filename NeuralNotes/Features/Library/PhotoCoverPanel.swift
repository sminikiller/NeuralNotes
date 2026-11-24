import SwiftUI
import PhotosUI
import ImageIO
import PencilKit
import NeuralNotesCore

@MainActor
struct PhotoCoverPanel: View {
    let notebook: Notebook
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var data: Data?
    @State private var busy = false
    @State private var error: String?
    @State private var design = CoverDesign()
    @State private var usesLastEditedPage = false
    @State private var pagePreview: UIImage?
    @State private var editingPaper = false
    @State private var template = PageTemplate()
    @State private var loadedTemplate = PageTemplate()
    @State private var imageChanged = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Aspetto", selection: $editingPaper) {
                    Text("Copertina").tag(false)
                    Text("Fogli").tag(true)
                }.pickerStyle(.segmented)
                if editingPaper {
                    Section {
                        Text("La carta scelta si applica alle nuove pagine. Puoi cambiare un foglio esistente da Carta nell’editor.")
                        if template.pdfFile != nil {
                            Button("Sostituisci il modello PDF con carta") {
                                template.pdfFile = nil; template.pdfIndex = nil
                                template.sourceWidth = nil; template.sourceHeight = nil
                            }
                        }
                    }
                    PageTemplateControls(template: $template).disabled(template.pdfFile != nil)
                } else {
                    coverControls
                }
                if busy { ProgressView("Preparazione foto…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .disabled(!loaded || busy)
            .navigationTitle("Aspetto · \(notebook.title)")
            .task {
                do {
                    let workspace = try library.workspace(notebook)
                    let catalog = try await workspace.catalog()
                    template = catalog.defaultPageTemplate ?? PageTemplate()
                    loadedTemplate = template
                    design = catalog.coverDesign ?? .suggested(id: notebook.id, title: notebook.title)
                    usesLastEditedPage = catalog.coverUsesLastEditedPage == true
                    if let file = catalog.coverImageFile {
                        data = try Data(contentsOf: await workspace.url(file)); preview = data.flatMap { UIImage(data: $0) }
                    }
                    loaded = true
                } catch { self.error = error.localizedDescription }
            }
            .task(id: loaded && usesLastEditedPage) {
                guard loaded && usesLastEditedPage else { return }
                do {
                    let image = try await LastEditedCover.image(workspace: library.workspace(notebook))
                    try Task.checkCancellation()
                    pagePreview = image
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
            .task(id: selection) {
                guard let selection else { return }
                busy = true; defer { busy = false }
                do {
                    guard let bytes = try await selection.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                    guard bytes.count <= 100 * 1024 * 1024,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 900] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                    let thumbnail = UIImage(cgImage: image)
                    guard let png = thumbnail.pngData() else { throw CocoaError(.fileWriteUnknown) }
                    preview = thumbnail; data = png; imageChanged = true; usesLastEditedPage = false; error = nil
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                try await library.workspace(notebook).updateAppearance(design: design, useLastEditedPage: usesLastEditedPage,
                                    image: imageChanged ? .replace(data) : .keep, template: template == loadedTemplate ? nil : template)
                                library.didEdit(notebook); library.coverRevision += 1; dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || !loaded).accessibilityIdentifier("saveCoverButton")
                }
            }
        }.interactiveDismissDisabled(busy)
    }

    @ViewBuilder private var coverControls: some View {
        Section {
            NotebookCoverView(notebook: notebook, photo: usesLastEditedPage ? pagePreview : preview,
                design: design, isPagePreview: usesLastEditedPage).frame(maxWidth: 300).frame(maxWidth: .infinity)
            Toggle("Ultima pagina modificata", isOn: $usesLastEditedPage)
                .accessibilityIdentifier("coverLastEditedPage")
            Text("La copertina mostra la pagina salvata più di recente, con inchiostro, immagini e PDF. Si aggiorna quando torni in libreria.").font(.caption)
            PhotosPicker(selection: $selection, matching: .images) { Label("Scegli una foto", systemImage: "photo.on.rectangle") }
            Button("Usa copertina a colori") { usesLastEditedPage = false; preview = nil; data = nil; imageChanged = true }
        }
        Section("Colore e motivo") {
            ColorPicker("Colore personalizzato", selection: Binding(get: { design.color?.color ?? notebook.cover.color }, set: { design.color = InkColor($0) }), supportsOpacity: false)
            Picker("Motivo", selection: $design.pattern) {
                ForEach(CoverPattern.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
        }
        Section("Simbolo") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                ForEach(CoverDesign.symbols, id: \.self) { symbol in
                    Button { design.symbol = symbol } label: { Image(systemName: symbol).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).background(design.symbol == symbol ? Brand.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(symbol)
                }
            }
        }
    }
}

@MainActor
struct LibraryNotebookCover: View {
    let notebook: Notebook
    let library: LibraryViewModel
    var compact = false
    @State private var photo: UIImage?
    @State private var design: CoverDesign?
    @State private var isPagePreview = false

    var body: some View {
        NotebookCoverView(notebook: notebook, compact: compact, photo: photo, design: design, isPagePreview: isPagePreview)
            .task(id: "\(notebook.updatedAt.timeIntervalSince1970)-\(library.coverRevision)") {
                do {
                    let workspace = try library.workspace(notebook)
                    let catalog = try await workspace.catalog(); design = catalog.coverDesign
                    isPagePreview = catalog.coverUsesLastEditedPage == true
                    if isPagePreview {
                        photo = try await LastEditedCover.image(workspace: workspace)
                    } else if let path = catalog.coverImageFile {
                        let url = try await workspace.url(path)
                        let bytes = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                        try Task.checkCancellation(); photo = UIImage(data: bytes)
                    } else { photo = nil }
                } catch { photo = nil }
            }
    }
}

@MainActor
enum LastEditedCover {
    static func image(workspace: DocumentWorkspace) async throws -> UIImage? {
        let pages = try await workspace.pages()
        let latest = pages.filter { $0.lastEditedAt != nil }.max { ($0.lastEditedAt ?? 0) < ($1.lastEditedAt ?? 0) }
        guard let page = latest ?? pages.first else { return nil }
        let drawing: PKDrawing
        do {
            let data = try await workspace.drawing(page)
            drawing = try data.map { try PKDrawing(data: $0) } ?? PKDrawing()
        } catch {
            guard let backup = page.previousDrawingFile else { throw error }
            let file = try await workspace.url(backup)
            drawing = try PKDrawing(data: Data(contentsOf: file))
        }
        try Task.checkCancellation()
        return try await DocumentServices.compositeImage(page: page, drawing: drawing, drawingLayerID: page.id, workspace: workspace, maxDimension: 700)
    }
}
