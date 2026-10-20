import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
struct PageBrowser: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var onlyBookmarks = false
    @State private var reorder = false
    @State private var renaming: PageSnapshot?
    @State private var title = ""
    @State private var busy = false

    private var visible: [PageSnapshot] { model.pages.filter { !onlyBookmarks || $0.isBookmarked == true } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Toggle("Solo segnalibri", isOn: $onlyBookmarks).padding().disabled(reorder)
                if reorder {
                    List {
                        ForEach(model.pages) { page in
                            Label(label(page), systemImage: page.isBookmarked == true ? "bookmark.fill" : "doc")
                        }
                        .onMove { indices, destination in
                            var pages = model.pages
                            pages.move(fromOffsets: indices, toOffset: destination)
                            Task {
                                busy = true; defer { busy = false }
                                await model.reorder(pages.map(\.id))
                            }
                        }
                    }.environment(\.editMode, .constant(.active))
                } else if visible.isEmpty {
                    ContentUnavailableView("Nessun segnalibro", systemImage: "bookmark", description: Text("Tieni premuta una pagina e aggiungila ai segnalibri."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230))], spacing: 20) {
                            ForEach(visible) { page in
                                Button {
                                    Task { await model.select(page); if model.page?.id == page.id { dismiss() } }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PageThumbnail(page: page, workspace: model.workspace)
                                            .overlay(alignment: .topTrailing) {
                                                if page.isBookmarked == true { Image(systemName: "bookmark.fill").padding(6).foregroundStyle(Brand.accent) }
                                            }
                                        Text(label(page)).font(.caption).lineLimit(2)
                                    }.padding(8).background(model.page?.id == page.id ? Brand.accent.opacity(0.16) : Brand.surface,
                                        in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(page.isBookmarked == true ? "Rimuovi segnalibro" : "Aggiungi segnalibro", systemImage: "bookmark") {
                                        Task { await model.setPageDetails(page, title: page.title, bookmarked: page.isBookmarked != true) }
                                    }
                                    Button("Rinomina pagina", systemImage: "pencil") { title = page.title ?? ""; renaming = page }
                                }
                            }
                        }.padding()
                    }
                }
            }.disabled(busy)
            .navigationTitle("Pagine · \(model.pages.count)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(reorder ? "Fine riordino" : "Riordina") { onlyBookmarks = false; reorder.toggle() } }
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
            }
            .alert("Nome della pagina", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titolo", text: $title)
                Button("Salva") {
                    if let page = renaming {
                        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await model.setPageDetails(page, title: value.isEmpty ? nil : value, bookmarked: page.isBookmarked == true) }
                    }
                    renaming = nil
                }
                Button("Annulla", role: .cancel) { renaming = nil }
            }
        }
    }

    private func label(_ page: PageSnapshot) -> String {
        let number = (model.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
        return page.title.map { "\(number) · \($0)" } ?? "Pagina \(number)"
    }
}

@MainActor
struct PageThumbnail: View {
    let page: PageSnapshot
    let workspace: DocumentWorkspace
    var maxDimension: CGFloat = 320
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "exclamationmark.triangle").frame(maxWidth: .infinity, minHeight: 160) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
        }
        .frame(maxWidth: .infinity).aspectRatio(page.width / page.height, contentMode: .fit)
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: page.revision) {
            do {
                let bytes = try await workspace.drawing(page)
                try Task.checkCancellation()
                let drawing = try bytes.map { try PKDrawing(data: $0) } ?? PKDrawing()
                image = DocumentServices.image(page: page, drawing: drawing, workspace: workspace, maxDimension: maxDimension)
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}
