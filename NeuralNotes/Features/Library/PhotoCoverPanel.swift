import SwiftUI
import PhotosUI
import ImageIO
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NotebookCoverView(notebook: notebook, photo: preview, design: design).frame(maxWidth: 300).frame(maxWidth: .infinity)
                    PhotosPicker(selection: $selection, matching: .images) { Label("Scegli una foto", systemImage: "photo.on.rectangle") }
                    Button("Usa copertina a colori", role: .destructive) { preview = nil; data = nil }
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
                if busy { ProgressView("Preparazione foto…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Copertina · \(notebook.title)")
            .task {
                do {
                    let workspace = try library.workspace(notebook)
                    let catalog = try await workspace.catalog()
                    design = catalog.coverDesign ?? .suggested(id: notebook.id, title: notebook.title)
                    if let file = catalog.coverImageFile {
                        data = try Data(contentsOf: await workspace.url(file)); preview = data.flatMap { UIImage(data: $0) }
                    }
                } catch { self.error = error.localizedDescription }
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
                    preview = UIImage(cgImage: image); data = preview?.pngData(); error = nil
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
                                try await library.workspace(notebook).setCoverAppearance(image: data, design: design)
                                library.didEdit(notebook); library.coverRevision += 1; dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy)
                }
            }
        }.interactiveDismissDisabled(busy)
    }
}

@MainActor
struct LibraryNotebookCover: View {
    let notebook: Notebook
    let library: LibraryViewModel
    var compact = false
    @State private var photo: UIImage?
    @State private var design: CoverDesign?

    var body: some View {
        NotebookCoverView(notebook: notebook, compact: compact, photo: photo, design: design)
            .task(id: "\(notebook.updatedAt.timeIntervalSince1970)-\(library.coverRevision)") {
                do {
                    let workspace = try library.workspace(notebook)
                    let catalog = try await workspace.catalog(); design = catalog.coverDesign
                    if let path = catalog.coverImageFile {
                        let url = try await workspace.url(path)
                        let bytes = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                        try Task.checkCancellation(); photo = UIImage(data: bytes)
                    } else { photo = nil }
                } catch { photo = nil }
            }
    }
}
