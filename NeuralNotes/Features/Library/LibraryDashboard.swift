import SwiftUI
import NeuralNotesCore

@MainActor
struct LibraryDashboard: View {
    let notebooks: [Notebook]
    let recent: [Notebook]
    let library: LibraryViewModel
    let create: () -> Void, importFile: () -> Void
    let open: (Notebook) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                quickAction("Nuova idea", subtitle: "Crea un quaderno", icon: "plus", action: create)
                quickAction("Importa", subtitle: "PDF o backup", icon: "square.and.arrow.down", action: importFile)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(notebooks.count)").font(.title2.bold())
                    Text("quaderni · \(notebooks.filter(\.isFavorite).count) preferiti").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !recent.isEmpty {
                HStack { Text("Riprendi da qui").font(.headline); Image(systemName: "clock").foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recent) { notebook in
                            Button { open(notebook) } label: {
                                HStack(spacing: 12) {
                                    LibraryNotebookCover(notebook: notebook, library: library, compact: true)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(notebook.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Label("Apri subito", systemImage: "arrow.up.right").font(.caption).foregroundStyle(Brand.accent)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(12).frame(width: 230, height: 84)
                                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityLabel("Riprendi \(notebook.title)").accessibilityIdentifier("resume-\(notebook.id)")
                        }
                    }
                }
            }
        }
    }
    private func quickAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(14).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
