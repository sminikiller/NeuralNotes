import SwiftUI
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func openPageLink(_ target: PageLinkTarget) async {
        guard target.documentID == workspace.documentID else { error = "Questo collegamento appartiene a un altro quaderno. Apri il quaderno di origine dalla libreria."; return }
        guard let targetPage = pages.first(where: { $0.id == target.pageID }) else { error = "La pagina collegata è stata rimossa. Puoi ripristinarla con Annulla o dal recupero del quaderno."; return }
        await select(targetPage)
    }
}

@MainActor
struct PageLinksPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var destination = ""
    private var links: [IndexedPageLink] { PageLinks.index(model.pages.map { $0.id == model.page?.id ? model.page ?? $0 : $0 }) }
    private var outgoing: [IndexedPageLink] { links.filter { $0.originPageID == model.page?.id } }
    private var incoming: [IndexedPageLink] { links.filter { $0.target.documentID == model.workspace.documentID && $0.target.pageID == model.page?.id } }
    var body: some View {
        NavigationStack {
            List {
                Section("Collega dalla pagina corrente") {
                    TextField("Etichetta facoltativa", text: $label)
                    Picker("Destinazione", selection: $destination) {
                        Text("Scegli una pagina").tag("")
                        ForEach(model.pages.filter { $0.id != model.page?.id }) { page in Text(title(page.id)).tag(page.id.uuidString) }
                    }
                    Button("Inserisci collegamento", systemImage: "link.badge.plus") { add() }.disabled(UUID(uuidString: destination) == nil)
                    Text("Con lo strumento Oggetti seleziona il testo collegato e toccalo di nuovo per aprire la fonte. I collegamenti sono inclusi nei backup.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Da questa pagina · \(outgoing.count)") {
                    ForEach(outgoing) { link in
                        Button { Task { await model.openPageLink(link.target); if model.page?.id == link.target.pageID { dismiss() } } } label: { Label(link.label, systemImage: "arrow.up.forward") }
                            .swipeActions { Button("Rimuovi collegamento", role: .destructive) { model.mutatePage("Rimuovi collegamento") { page in if let i = page.texts.firstIndex(where: { $0.id == link.textID }) { page.texts[i].pageLink = nil } } } }
                    }
                }
                Section("Collegamenti in entrata · \(incoming.count)") {
                    ForEach(incoming) { link in
                        Button { Task { await model.openPageLink(PageLinkTarget(documentID: model.workspace.documentID, pageID: link.originPageID)); dismiss() } } label: {
                            VStack(alignment: .leading) { Text(title(link.originPageID)); Text(link.label).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }
                }
            }.navigationTitle("Collegamenti e fonti")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
    private func title(_ id: UUID) -> String {
        guard let i = model.pages.firstIndex(where: { $0.id == id }) else { return "Pagina rimossa" }
        return model.pages[i].title.map { "\(i + 1) · \($0)" } ?? "Pagina \(i + 1)"
    }
    private func add() {
        guard let id = UUID(uuidString: destination), model.pages.contains(where: { $0.id == id }) else { return }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = TextElement(text: "↗ " + (name.isEmpty ? title(id) : String(name.prefix(240))))
        text.pageLink = PageLinkTarget(documentID: model.workspace.documentID, pageID: id)
        model.mutatePage("Inserisci collegamento") { $0.texts.append(text) }; label = ""; destination = ""
    }
}
