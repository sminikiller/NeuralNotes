import SwiftUI
import NeuralNotesCore

@MainActor
struct MoveSelectionMenu: View {
    @Bindable var model: EditorViewModel
    @State private var showing = false
    var body: some View {
        Button("Copia o sposta in un’altra pagina", systemImage: "doc.on.doc") { showing = true }
            .accessibilityIdentifier("selectionTransfer")
            .disabled(model.selectedIDs.isEmpty && !model.selectionIncludesInk)
            .sheet(isPresented: $showing) { SelectionDestinationPanel(model: model) }
    }
}

@MainActor
struct SelectionDestinationPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copy = false
    @State private var query = ""
    @State private var busy = false
    private struct Row: Identifiable { let index: Int; let page: PageSnapshot; var id: UUID { page.id } }
    private var rows: [Row] {
        model.pages.enumerated().compactMap { index, page in
            guard page.id != model.page?.id else { return nil }
            let label = "\(index + 1) \(page.title ?? "")"
            return query.isEmpty || label.localizedCaseInsensitiveContains(query) ? Row(index: index, page: page) : nil
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Operazione", selection: $copy) {
                    Text("Sposta").tag(false); Text("Copia").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal).disabled(busy)
                HStack {
                    Button("Nuova prima", systemImage: "doc.badge.plus") { transfer(nil, after: false) }
                        .accessibilityIdentifier("selectionNewPageBefore")
                    Button("Nuova dopo", systemImage: "doc.badge.plus") { transfer(nil, after: true) }
                        .accessibilityIdentifier("selectionNewPageAfter")
                }.buttonStyle(.bordered).disabled(busy || model.pages.count >= DocumentWorkspace.maximumPageEditPages)
                if busy { ProgressView(copy ? "Copia della selezione…" : "Spostamento della selezione…") }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 170))], spacing: 16) {
                        ForEach(rows) { row in destination(row) }
                    }.padding()
                    if rows.isEmpty { Text("Scegli una nuova pagina oppure cambia la ricerca.").font(.callout).foregroundStyle(.secondary).padding() }
                }.disabled(busy)
                Text("Una sola azione Annulla ripristina entrambe le pagine. La nuova pagina mantiene carta e formato della pagina di origine.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }.padding(.vertical)
                .searchable(text: $query, prompt: "Numero o titolo della pagina")
                .navigationTitle("Destinazione della selezione")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .alert("Selezione non trasferita", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("OK", role: .cancel) { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
    }
    private func destination(_ row: Row) -> some View {
        Button { transfer(row.id) } label: {
            VStack(spacing: 6) {
                PageThumbnail(page: row.page, workspace: model.workspace, maxDimension: 200).frame(height: 140).clipped()
                Text(row.page.title.map { "\(row.index + 1) · \($0)" } ?? "Pagina \(row.index + 1)")
                    .font(.callout).lineLimit(2)
            }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("selectionDestination-\(row.id)")
    }
    private func transfer(_ id: UUID?, after: Bool = true) {
        guard !busy else { return }; busy = true; model.error = nil
        Task {
            await model.transferSelection(to: id, copy: copy, newPageAfter: after)
            busy = false
            if model.error == nil { dismiss() }
        }
    }
}
