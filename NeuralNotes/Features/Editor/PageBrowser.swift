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
    @State private var sectionFilter = ""
    @State private var managingSections = false
    @State private var showingLinks = false
    @State private var deleting: Set<UUID> = []
    @State private var confirmingDeletion = false
    @State private var selected: Set<UUID> = []
    @State private var selecting = false
    @State private var showingTrash = false

    private var outline: [(section: NotebookSection, depth: Int)] { NotebookSections.outline(model.sections) }
    private var visible: [PageSnapshot] {
        let assigned = Set(model.sections.flatMap(\.pageIDs))
        let selected = UUID(uuidString: sectionFilter).map { NotebookSections.pages(in: $0, sections: model.sections) }
        return model.pages.filter { page in
            (!onlyBookmarks || page.isBookmarked == true) &&
            (sectionFilter == "unassigned" ? !assigned.contains(page.id) : selected?.contains(page.id) ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            pageContents
            .navigationTitle("Pagine · \(model.pages.count)")
            .confirmationDialog("Spostare \(deleting.count) pagine nel cestino?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Sposta nel cestino", role: .destructive) {
                    let ids = deleting; deleting = []
                    Task { busy = true; defer { busy = false }; await model.deletePages(ids); selected.subtract(ids) }
                }
            } message: { Text("Puoi annullare l’eliminazione. I file restano recuperabili.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(reorder ? "Fine riordino" : "Riordina") { onlyBookmarks = false; selecting = false; selected = []; reorder.toggle() } }
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button(selecting ? "Fine selezione" : "Seleziona") { selecting.toggle(); selected = []; reorder = false } }
                ToolbarItem(placement: .bottomBar) { Button("Pagine eliminate", systemImage: "clock.arrow.circlepath") { showingTrash = true }.labelStyle(.titleAndIcon) }
                ToolbarItem(placement: .bottomBar) {
                    if selecting { Button("Elimina \(selected.count)", role: .destructive) { requestDeletion(selected) }.disabled(selected.isEmpty) }
                }
                ToolbarItem(placement: .bottomBar) {
                    if selecting { Button("Tutte") { selected = Set(visible.map(\.id)) } }
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu("Organizza", systemImage: "folder") {
                        Button("Sezioni", systemImage: "folder") { managingSections = true }
                        Button("Collegamenti", systemImage: "link") { showingLinks = true }
                    }
                }
            }
            .sheet(isPresented: $managingSections) { SectionsPanel(model: model) }
            .sheet(isPresented: $showingLinks) { PageLinksPanel(model: model) }
            .sheet(isPresented: $showingTrash) { PageTrashPanel(model: model) }
            .task {
                do { model.sections = try await model.workspace.catalog().sections ?? [] }
                catch { model.error = error.localizedDescription }
            }
            .onChange(of: model.sections) { _, sections in
                if let id = UUID(uuidString: sectionFilter), !sections.contains(where: { $0.id == id }) { sectionFilter = "" }
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

    private var pageContents: some View {
        VStack(spacing: 0) {
            Toggle("Solo segnalibri", isOn: $onlyBookmarks).padding().disabled(reorder)
            if !model.sections.isEmpty && !reorder { sectionPicker.padding(.horizontal).padding(.bottom, 8) }
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
                ContentUnavailableView("Nessuna pagina in questa vista", systemImage: "doc", description: Text("Cambia filtro o assegna una pagina a questa sezione dal menu dell’anteprima."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230))], spacing: 20) {
                        ForEach(visible) { page in
                            pageCard(page)
                        }
                    }.padding()
                }
            }
        }.disabled(busy)

    }

    private func pageCard(_ page: PageSnapshot) -> some View {
        VStack(spacing: 2) {
            Button {
                if selecting {
                    if selected.contains(page.id) { selected.remove(page.id) } else { selected.insert(page.id) }
                    return
                }
                Task { await model.select(page); if model.page?.id == page.id { dismiss() } }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    PageThumbnail(page: page, workspace: model.workspace)
                        .overlay(alignment: .topTrailing) {
                            if selecting { Image(systemName: selected.contains(page.id) ? "checkmark.circle.fill" : "circle").font(.title2).padding(6).foregroundStyle(Brand.accent) }
                            else if page.isBookmarked == true { Image(systemName: "bookmark.fill").padding(6).foregroundStyle(Brand.accent) }
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
                assignmentMenu(page)
                Button("Elimina pagina", systemImage: "trash", role: .destructive) { requestDeletion([page.id]) }
            }
            if !selecting {
                Button("Elimina pagina", systemImage: "trash", role: .destructive) { requestDeletion([page.id]) }
                    .labelStyle(.titleAndIcon).buttonStyle(.bordered).controlSize(.small)
                    .frame(minHeight: 44).accessibilityIdentifier("deletePage-\(page.id)")
            }
        }
    }

    private func requestDeletion(_ ids: Set<UUID>) {
        deleting = ids; confirmingDeletion = !ids.isEmpty
    }

    private var sectionPicker: some View {
        Picker("Sezione", selection: $sectionFilter) {
            Text("Tutte le pagine").tag("")
            Text("Senza sezione").tag("unassigned")
            ForEach(outline, id: \.section.id) { row in Text(String(repeating: "  ", count: row.depth) + row.section.title).tag(row.section.id.uuidString) }
        }.pickerStyle(.menu)
    }

    private func assignmentMenu(_ page: PageSnapshot) -> some View {
        Menu("Sposta nella sezione", systemImage: "folder") {
            Button("Senza sezione") { assign(page, sectionID: nil) }
            ForEach(outline, id: \.section.id) { row in
                Button(String(repeating: "  ", count: row.depth) + row.section.title) { assign(page, sectionID: row.section.id) }
            }
            Button("Gestisci sezioni…") { managingSections = true }
        }
    }
    private func assign(_ page: PageSnapshot, sectionID: UUID?) {
        Task { busy = true; defer { busy = false }; _ = await model.changeSections { try await $0.assignPages([page.id], toSection: sectionID) } }
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
