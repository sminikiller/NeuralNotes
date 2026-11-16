import SwiftUI
import NeuralNotesCore

@MainActor
struct StudyKitPanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var color = StudyColor.blue
    @State private var template = StudyDiagramTemplate.mindMap
    @State private var oval = false
    @State private var list = "Prima idea\n  Dettaglio\nSeconda idea"
    @State private var listTitle = "Concetti chiave"
    @State private var listKind = 0
    @State private var noteKind = StudyNoteKind.important
    @State private var note = ""
    @State private var tapeStyle = StudyTapeStyle.solid
    @State private var tapeWidth = 240.0
    @State private var tapeHeight = 32.0
    @State private var sectionsOpen = false
    @State private var linksOpen = false
    @State private var editingNote: StudyNoteTarget?
    @AppStorage("study.chapterTabs") private var chapterTabs = true
    private var currentTape: StudyTape? { model.page?.tapes?.first { $0.id == model.selectedObjectID } }
    private var noteRows: [StudyNoteTarget] {
        model.pages.flatMap { stored -> [StudyNoteTarget] in
            let page = model.page?.id == stored.id ? model.page! : stored
            return page.texts.filter { $0.studyNote != nil }.map { StudyNoteTarget(pageID: page.id, text: $0) }
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Studio", selection: $tab) {
                    Text("Inserisci").tag(0); Text("Ripasso").tag(1); Text("Post-it").tag(2); Text("Capitoli").tag(3)
                }.pickerStyle(.segmented).padding()
                Form {
                    if tab == 0 { insertSections }
                    if tab == 1 { reviewSections }
                    if tab == 2 { notesSections }
                    if tab == 3 { chapterSections }
                }
            }.navigationTitle("Studio sul foglio")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
                .sheet(isPresented: $sectionsOpen) { SectionsPanel(model: model) }
                .sheet(isPresented: $linksOpen) { PageLinksPanel(model: model) }
                .sheet(item: $editingNote) { StudyNoteEditor(model: model, target: $0) }
                .onAppear {
                    if model.page?.texts.first(where: { $0.id == model.selectedObjectID })?.studyNote != nil { tab = 2 }
                    if let tape = currentTape { tab = 1; color = tape.color ?? .yellow; tapeStyle = tape.style ?? .solid; tapeWidth = tape.width; tapeHeight = tape.height }
                }
        }
    }
    private var colors: some View {
        Picker("Colore", selection: $color) {
            ForEach(StudyColor.allCases, id: \.self) { value in Label(value.title, systemImage: "circle.fill").foregroundStyle(value.ink.color).tag(value) }
        }
    }
    @ViewBuilder private var insertSections: some View {
        Section("Schema o mappa") {
            Picker("Modello", selection: $template) { ForEach(StudyDiagramTemplate.allCases, id: \.self) { Text($0.title).tag($0) } }
            colors
            Toggle("Nodi ovali", isOn: $oval)
            Text(template.labels.joined(separator: " → ")).font(.callout).foregroundStyle(.secondary)
            Button("Inserisci schema", systemImage: "point.3.connected.trianglepath.dotted") {
                model.insertStudyDiagram(template, color: color, oval: oval); dismiss()
            }.disabled(!model.canEditActiveLayer).accessibilityIdentifier("insertStudyDiagram")
            Text("Seleziona un nodo e trascina dal bordo per collegarlo. Tocca il + sul bordo per un nuovo ramo. Doppio tap sul nodo o sulla freccia per modificare l’etichetta. Le frecce seguono gli spostamenti.").font(.caption)
        }
        Section("Elenco") {
            TextField("Titolo", text: $listTitle)
            Picker("Stile", selection: $listKind) { Text("Punti").tag(0); Text("Numeri").tag(1); Text("Checklist").tag(2) }.pickerStyle(.segmented)
            TextEditor(text: $list).frame(minHeight: 130).accessibilityIdentifier("studyListText")
            Text("Una voce per riga; due spazi iniziali per un sottoelenco. Dopo l’inserimento, il campo testo mantiene colori, rientri e formattazione.").font(.caption).foregroundStyle(.secondary)
            Button("Inserisci elenco", systemImage: "list.bullet") {
                model.insertStudyList(list, title: listTitle, kind: listKind, color: color); dismiss()
            }.disabled(!model.canEditActiveLayer || StudyDiagrams.listLabels(list).isEmpty)
            Button("Crea mappa dall’elenco", systemImage: "arrow.triangle.branch") {
                let outline = StudyDiagrams.outline(list, title: listTitle)
                model.insertStudyDiagram(.mindMap, labels: outline.labels, parents: outline.parents, color: color, oval: oval); dismiss()
            }.disabled(!model.canEditActiveLayer || StudyDiagrams.listLabels(list).isEmpty || StudyDiagrams.listLabels(list).count > 15)
            if StudyDiagrams.listLabels(list).count > 15 { Text("Una mappa contiene fino a 15 voci: dividi gli elenchi più lunghi in più mappe.").font(.caption) }
            if let selected = model.page?.texts.first(where: { $0.id == model.selectedObjectID }) {
                Button("Usa il testo selezionato") { list = selected.text }
            }
        }
        Section("Collegamenti") { Button("Collega pagine e fonti", systemImage: "link") { linksOpen = true } }
    }
    @ViewBuilder private var reviewSections: some View {
        Section("Scotch") {
            colors
            Picker("Aspetto", selection: $tapeStyle) { ForEach(StudyTapeStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
            Stepper("Larghezza: \(Int(tapeWidth)) pt", value: $tapeWidth, in: 12...min(20000, max(12, model.page?.width ?? 768)), step: 8)
            Stepper("Altezza: \(Int(tapeHeight)) pt", value: $tapeHeight, in: 12...min(20000, max(12, model.page?.height ?? 1024)), step: 4)
            Button(currentTape == nil ? "Inserisci scotch" : "Applica allo scotch selezionato", systemImage: "rectangle.fill") {
                if currentTape == nil { model.addStudyTape(color: color, style: tapeStyle, width: tapeWidth, height: tapeHeight) }
                else if let id = model.selectedObjectID { model.styleStudyTape(id: id, color: color, style: tapeStyle, width: tapeWidth, height: tapeHeight) }
                dismiss()
            }.disabled(!model.canEditActiveLayer).accessibilityIdentifier("insertStudyTape")
            Text("Sposta e ridimensiona con Oggetti. Con un altro strumento, tocca lo scotch con il dito per scoprire o ricoprire la parola. Trasparente lascia intravedere il contenuto.").font(.caption)
        }
        Section("Ripeti la pagina") {
            Text("\(model.page?.tapes?.count ?? 0) risposte · il ripasso riguarda il livello attivo modificabile.")
            Button("Inizia ripasso", systemImage: "eye.slash") { model.beginStudyReview(); dismiss() }
                .disabled(model.page?.tapes?.isEmpty != false).accessibilityIdentifier("startStudyReview")
            Button("Copri tutte") { model.setStudyTapes(revealed: false) }
            Button("Scopri tutte") { model.setStudyTapes(revealed: true) }
            Text("Durante il ripasso il foglio scorre, ma la penna non aggiunge tratti. Nell’esportazione PDF dei livelli puoi scegliere risposte coperte o senza scotch.").font(.caption)
        }
    }
    @ViewBuilder private var notesSections: some View {
        Section("Nuovo post-it") {
            Picker("Tipo", selection: $noteKind) { ForEach(StudyNoteKind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) } }
            colors
            TextField("Scrivi il richiamo", text: $note, axis: .vertical).lineLimit(2...6)
            Button("Inserisci post-it", systemImage: "note.text") { model.insertStudyNote(text: note, kind: noteKind, color: color); dismiss() }
                .disabled(!model.canEditActiveLayer).accessibilityIdentifier("insertStudyNote")
        }
        Section("Richiami del quaderno · \(noteRows.count)") {
            if noteRows.isEmpty { Text("I post-it saranno raccolti qui, con il collegamento alla pagina.").foregroundStyle(.secondary) }
            ForEach(noteRows) { row in
                HStack {
                    Button {
                        Task {
                            if let target = model.pages.first(where: { $0.id == row.pageID }) { await model.select(target) }
                            if model.page?.id == row.pageID { model.tool = .objects; model.selectedObjectID = row.id; model.configureTool(); dismiss() }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Label(row.text.studyNote?.kind.title ?? "Post-it", systemImage: row.text.studyNote?.kind.icon ?? "note.text")
                            Text(row.text.text).lineLimit(2).font(.caption)
                            Text("Pagina \((model.pages.firstIndex { $0.id == row.pageID } ?? 0) + 1)").font(.caption2)
                        }
                    }
                    Spacer()
                    Button("Modifica") { editingNote = row }.disabled(row.pageID != model.page?.id)
                }
            }
        }
    }
    @ViewBuilder private var chapterSections: some View {
        Section {
            Toggle("Linguette colorate sul bordo", isOn: $chapterTabs)
            Button("Crea e organizza capitoli", systemImage: "folder.badge.plus") { sectionsOpen = true }
            Text("I capitoli usano le sezioni del quaderno. Assegna la pagina corrente qui oppure più pagine dal browser. Le linguette seguono le pagine anche dopo un riordino.").font(.caption)
        }
        Section("Pagina corrente") {
            ForEach(NotebookSections.outline(model.sections), id: \.section.id) { row in
                Button {
                    guard let id = model.page?.id else { return }
                    Task { _ = await model.changeSections { try await $0.assignPages([id], toSection: row.section.id) } }
                } label: {
                    Label(String(repeating: "  ", count: row.depth) + row.section.title,
                          systemImage: row.section.pageIDs.contains(model.page?.id ?? UUID()) ? "checkmark.circle.fill" : "circle")
                }
            }
        }
    }
}

struct StudyNoteTarget: Identifiable {
    let pageID: UUID
    let text: TextElement
    var id: UUID { text.id }
}

@MainActor
struct StudyNoteEditor: View {
    let model: EditorViewModel
    let target: StudyNoteTarget
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TextElement(text: "")
    @State private var color = StudyColor.yellow
    var body: some View {
        NavigationStack {
            Form {
                RichTextEditor(text: $draft).frame(minHeight: 180)
                Picker("Colore", selection: $color) { ForEach(StudyColor.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Richiudi in linguetta", isOn: Binding(get: { draft.studyNote?.collapsed == true }, set: { draft.studyNote?.collapsed = $0 }))
            }.navigationTitle("Post-it")
                .onAppear { draft = target.text; color = StudyColor.allCases.first { $0.ink == draft.background } ?? .yellow }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            guard model.page?.id == target.pageID else { return }
                            draft.background = color.ink
                            model.mutatePage("Modifica post-it") { page in if let i = page.texts.firstIndex(where: { $0.id == target.id }) { page.texts[i] = draft } }
                            dismiss()
                        }
                    }
                }
        }
    }
}

@MainActor
struct StudyReviewControls: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        HStack(spacing: 12) {
            Button { model.setStudyTapes(revealed: false) } label: { Image(systemName: "eye.slash") }.accessibilityLabel("Ricopri risposte")
            Button("Scopri prossima") { model.revealNextStudyTape() }
            Button("Fine") { model.endStudyReview() }
        }.font(.callout).padding(12).background(.regularMaterial, in: Capsule()).accessibilityIdentifier("studyReviewControls")
    }
}

@MainActor
struct StudyChapterTabs: View {
    @Bindable var model: EditorViewModel
    @AppStorage("study.chapterTabs") private var visible = true
    private var sections: [NotebookSection] { model.sections.filter { $0.color != nil && !$0.pageIDs.isEmpty } }
    var body: some View {
        if visible && !sections.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(sections) { section in
                        Button {
                            if let target = model.pages.first(where: { section.pageIDs.contains($0.id) }) { Task { await model.select(target) } }
                        } label: {
                            Text(section.title).font(.caption).lineLimit(2).frame(width: 74, height: 44)
                                .foregroundStyle(.black).background((section.color ?? .blue).ink.color, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(section.pageIDs.contains(model.page?.id ?? UUID()) ? Color.primary : .clear, lineWidth: 2))
                        }.accessibilityLabel("Capitolo \(section.title)")
                    }
                }.padding(3)
            }.frame(width: 80, height: min(240, CGFloat(sections.count * 48 + 6)))
        }
    }
}
