import SwiftUI
import NeuralNotesCore

@MainActor
struct SectionsPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: NotebookSection?
    @State private var title = ""
    @State private var parent = ""
    @State private var formVisible = false
    @State private var busy = false
    @State private var error: String?
    @State private var collapsed = Set<UUID>()
    private var outline: [(section: NotebookSection, depth: Int)] { NotebookSections.visibleOutline(model.sections, collapsed: collapsed) }
    private var parents: [(section: NotebookSection, depth: Int)] {
        NotebookSections.outline(model.sections).filter { row in
            guard let editing else { return row.depth < 11 }
            var cursor: UUID? = row.section.id
            for _ in 0..<12 {
                guard let id = cursor else { break }
                if id == editing.id { return false }
                cursor = model.sections.first { $0.id == id }?.parentID
            }
            return row.depth < 11
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if formVisible { sectionForm }
                if outline.isEmpty && !formVisible {
                    ContentUnavailableView("Organizza il quaderno", systemImage: "folder", description: Text("Crea sezioni e sottosezioni, poi assegna le pagine dalla loro anteprima."))
                }
                ForEach(outline, id: \.section.id) { row in
                    sectionRow(row.section, depth: row.depth)
                }.onMove(perform: move)
            }.navigationTitle("Sezioni")
                .disabled(busy)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .primaryAction) { Button("Nuova sezione", systemImage: "folder.badge.plus") { edit(nil) }.disabled(formVisible) }
                    ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
                }
        }
    }
    private var sectionForm: some View {
        Section(editing == nil ? "Nuova sezione" : "Modifica sezione") {
            TextField("Titolo", text: $title).accessibilityIdentifier("sectionTitleField")
            Picker("Dentro", selection: $parent) {
                Text("Livello principale").tag("")
                ForEach(parents, id: \.section.id) { row in Text(String(repeating: "  ", count: row.depth) + row.section.title).tag(row.section.id.uuidString) }
            }
            HStack {
                Button("Annulla", role: .cancel) { formVisible = false }
                Spacer()
                Button("Salva") {
                    let section = NotebookSection(id: editing?.id ?? UUID(), title: title, parentID: UUID(uuidString: parent))
                    Task {
                        busy = true; defer { busy = false }
                        if await model.changeSections({ try await $0.saveSection(section) }) { formVisible = false; error = nil }
                        else { error = model.error }
                    }
                }.disabled((try? LibraryName.validated(title)) == nil)
            }
        }
    }
    private func sectionRow(_ section: NotebookSection, depth: Int) -> some View {
        let ids = NotebookSections.pages(in: section.id, sections: model.sections)
        let count = model.pages.filter { ids.contains($0.id) }.count
        return HStack {
            if model.sections.contains(where: { $0.parentID == section.id }) {
                Button { if !collapsed.insert(section.id).inserted { collapsed.remove(section.id) } } label: {
                    Image(systemName: collapsed.contains(section.id) ? "chevron.right" : "chevron.down").frame(width: 32, height: 44)
                }.buttonStyle(.borderless).accessibilityLabel("\(collapsed.contains(section.id) ? "Espandi" : "Comprimi") \(section.title)")
            } else { Color.clear.frame(width: 32, height: 1) }
            Label(section.title, systemImage: "folder").padding(.leading, CGFloat(depth) * 12)
            Spacer(); Text("\(count)").foregroundStyle(.secondary)
            Menu {
                Button("Modifica", systemImage: "pencil") { edit(section) }
                Button("Rientra sotto la sezione precedente", systemImage: "increase.indent") { transform { try NotebookSections.indenting(section.id, in: $0) } }
                    .disabled((try? NotebookSections.indenting(section.id, in: model.sections)) == model.sections)
                Button("Riduci rientro", systemImage: "decrease.indent") { transform { try NotebookSections.outdenting(section.id, in: $0) } }.disabled(section.parentID == nil)
                Button("Nuova sottosezione", systemImage: "folder.badge.plus") { edit(nil); parent = section.id.uuidString }
                Button("Elimina sezione vuota", systemImage: "trash", role: .destructive) {
                    Task { busy = true; defer { busy = false }; if !(await model.changeSections { try await $0.removeSection(section.id) }) { error = model.error } }
                }.disabled(count != 0 || model.sections.contains { $0.parentID == section.id })
            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Azioni sezione \(section.title)")
        }
    }
    private func transform(_ action: @escaping ([NotebookSection]) throws -> [NotebookSection]) {
        let expected = model.sections
        Task {
            busy = true; defer { busy = false }
            do {
                let value = try action(expected)
                if !(await model.changeSections { try await $0.replaceSections(value, expected: expected) }) { error = model.error }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func move(from source: IndexSet, to destination: Int) {
        let visible = outline, selected = source.compactMap { visible.indices.contains($0) ? visible[$0].section : nil }
        let selectedIDs = Set(selected.map(\.id))
        let remaining = visible.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let targetIndex = destination - source.filter { $0 < destination }.count
        let target = remaining.indices.contains(targetIndex) ? remaining[targetIndex].section : nil
        transform { original in
            var result = original
            for item in selected {
                var ancestor = item.parentID, covered = false
                while let id = ancestor {
                    if selectedIDs.contains(id) { covered = true; break }
                    ancestor = original.first { $0.id == id }?.parentID
                }
                if covered { continue }
                let parent: UUID? = target == nil ? item.parentID : target!.parentID
                result = try NotebookSections.moving(item.id, to: parent, before: target?.id, in: result)
            }
            return result
        }
    }
    private func edit(_ section: NotebookSection?) {
        editing = section; title = section?.title ?? ""; parent = section?.parentID?.uuidString ?? ""; formVisible = true
    }
}
