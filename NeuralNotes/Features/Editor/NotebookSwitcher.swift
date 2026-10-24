import SwiftUI
import NeuralNotesCore

struct NotebookSwitching {
    let notebooks: [Notebook]
    let selected: UUID
    let select: (UUID) -> Void
    let close: (UUID) -> Void
    let open: () -> Void
}

/// Open documents live in the title, leaving the full height to the editor.
@MainActor
struct NotebookSwitcher: View {
    let title: String
    let switching: NotebookSwitching
    @State private var expanded = false
    @State private var opening = false

    var body: some View {
        Button { expanded = true } label: {
            HStack(spacing: 6) {
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                if switching.notebooks.count > 1 {
                    Text("\(switching.notebooks.count)").font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Brand.accent.opacity(0.15), in: Capsule())
                }
            }.frame(minHeight: 44).frame(maxWidth: 220).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Quaderni aperti: \(title)")
        .accessibilityValue("\(switching.notebooks.count) schede")
        .accessibilityIdentifier("editorNotebookSwitcher")
        .popover(isPresented: $expanded) { contents }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quaderni aperti").font(.headline)
                Spacer()
                Button("Chiudi elenco", systemImage: "xmark") { expanded = false }.labelStyle(.iconOnly)
            }.padding(.bottom, 4)
            ForEach(switching.notebooks) { notebook in row(notebook) }
            Divider().padding(.vertical, 4)
            Button {
                // Wait for this popover to finish dismissing before presenting the chooser.
                opening = true; expanded = false
            } label: { Label("Apri un altro quaderno", systemImage: "plus") }
                .frame(minHeight: 44).disabled(switching.notebooks.count >= 6)
                .accessibilityIdentifier("editorOpenNotebook")
        }
        .padding(16).frame(width: 320)
        .presentationCompactAdaptation(.popover)
        .onDisappear { if opening { opening = false; switching.open() } }
    }

    private func row(_ notebook: Notebook) -> some View {
        HStack(spacing: 8) {
            Button {
                expanded = false; switching.select(notebook.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: switching.selected == notebook.id ? "checkmark" : "book.closed")
                        .frame(width: 20).foregroundStyle(Brand.accent)
                    Text(notebook.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("deskSelect-\(notebook.id)")
            Button {
                expanded = false; switching.close(notebook.id)
            } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Chiudi scheda \(notebook.title)")
        }.font(.subheadline)
    }
}
